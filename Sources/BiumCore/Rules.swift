import Foundation

/// The catalogue of things worth reclaiming.
///
/// Order is meaningful: specific rules come before generic sweeps so that, for
/// example, `~/Library/Caches/Homebrew` is reported under Homebrew rather than
/// being swallowed anonymously by the catch-all user-cache rule. The scanner
/// claims paths in this order and a later rule never re-offers a claimed path.
public enum Rules {

    static func h(_ suffix: String) -> String {
        suffix.isEmpty ? Guardrails.home : "\(Guardrails.home)/\(suffix)"
    }

    public static func all() -> [Rule] {
        // Order matters: staleCopies and the tool-specific rules claim their
        // paths before the generic cache sweeps get a chance to.
        staleCopies() + xcode() + packageManagers() + modelCaches() + apps()
            + browsers() + genericCaches() + userFiles() + actions() + deepProjects()
    }

    public static func rule(id: String) -> Rule? {
        all().first { $0.id == id }
    }

    // MARK: - Superseded copies
    //
    // These are the quiet ones: nothing looks wrong in Finder, but an editor
    // that has updated itself two dozen times is sitting on two dozen copies
    // of every extension.

    static func staleCopies() -> [Rule] {
        [
            Rule(
                id: "editor-orphan-extensions",
                title: t("Unregistered editor extensions (old versions, install leftovers)", "등록되지 않은 에디터 확장 (옛 버전 / 설치 잔여물)"),
                detail: t("Extension folders the editor does not list in its own extensions.json: old versions an update failed to remove, or debris from an interrupted install. Extensions actually in use are never touched.", "에디터가 자기 extensions.json에 올려두지 않은 확장 폴더입니다. 업데이트할 때 옛 버전이 지워지지 않고 남거나, 설치가 중단되며 생긴 것들입니다. 실제로 쓰이는 확장은 건드리지 않습니다."),
                category: .apps, safety: .safe,
                target: .orphanedEditorExtensions([
                    h(".vscode/extensions"),
                    h(".vscode-insiders/extensions"),
                    h(".vscode-server/extensions"),
                    h(".cursor/extensions"),
                    h(".windsurf/extensions"),
                ])
            ),
            Rule(
                id: "jetbrains-old-versions",
                title: t("Superseded JetBrains IDE settings and plugins", "구버전 JetBrains IDE 설정 / 플러그인"),
                detail: t("Settings and plugins belonging to IDE releases you no longer run. The two newest versions of each product are kept. Launching an older version again starts it with default settings.", "더 이상 쓰지 않는 IDE 릴리스의 설정과 플러그인입니다. 제품별로 최신 2개 버전은 남깁니다. 해당 버전을 다시 실행하면 설정이 초기화됩니다."),
                category: .apps, safety: .review,
                target: .staleVersionedDirectories(
                    roots: [
                        h("Library/Application Support/JetBrains"),
                        h("Library/Caches/JetBrains"),
                        h("Library/Logs/JetBrains"),
                    ],
                    keepNewest: 2
                )
            ),
        ]
    }

    // MARK: - ML / model caches
    //
    // Individually enormous and trivially re-downloadable, but re-downloading
    // is measured in tens of gigabytes, so never SAFE.

    static func modelCaches() -> [Rule] {
        [
            Rule(
                id: "huggingface-cache",
                title: t("Hugging Face and model caches", "Hugging Face / 모델 캐시"),
                detail: t("Downloaded model weights. Re-downloadable, but large and slow to fetch again. Check whether a model you are actively using lives here.", "내려받은 모델 가중치입니다. 다시 받을 수 있지만 용량이 크고 시간이 오래 걸립니다. 지금 쓰는 모델이 있는지 확인하세요."),
                category: .packageManager, safety: .review,
                target: .contentsOf([
                    h(".cache/huggingface"),
                    h(".cache/torch"),
                    h(".cache/lm-studio"),
                    h("Library/Caches/huggingface"),
                ])
            ),
            Rule(
                id: "claude-vm-bundles",
                title: t("Claude desktop VM bundles", "Claude 데스크톱 VM 번들"),
                detail: t("VM images for the local agent sandbox. The app downloads them again when it needs them. Conversations and settings live elsewhere and are unaffected.", "로컬 에이전트 샌드박스용 VM 이미지입니다. 앱이 필요할 때 다시 내려받습니다. 대화 기록이나 설정은 별도 위치라 영향이 없습니다."),
                category: .apps, safety: .review,
                target: .contentsOf([h("Library/Application Support/Claude/vm_bundles")])
            ),
            Rule(
                id: "dot-cache",
                title: t("Other ~/.cache entries", "그 밖의 ~/.cache 항목"),
                detail: t("Entries in ~/.cache not claimed by a more specific rule above. Data the owning tools can rebuild.", "위 규칙에 해당하지 않는 ~/.cache 항목입니다. 도구들이 다시 만들 수 있는 데이터입니다."),
                category: .systemCache, safety: .safe,
                target: .contentsOf([h(".cache")])
            ),
        ]
    }

    // MARK: - Xcode & simulators

    static func xcode() -> [Rule] {
        [
            Rule(
                id: "xcode-deriveddata",
                title: "Xcode DerivedData",
                detail: t("Intermediate build products and indexes. Removing them makes the next build slower once; your sources are untouched.", "빌드 중간 산출물과 인덱스. 지우면 다음 빌드가 한 번 느려질 뿐 원본에는 영향이 없습니다."),
                category: .xcode, safety: .safe,
                target: .contentsOf([h("Library/Developer/Xcode/DerivedData")])
            ),
            Rule(
                id: "xcode-caches",
                title: t("Xcode caches", "Xcode 캐시"),
                detail: t("Caches Xcode rebuilds on its own.", "Xcode가 스스로 다시 만드는 캐시입니다."),
                category: .xcode, safety: .safe,
                target: .contentsOf([
                    h("Library/Caches/com.apple.dt.Xcode"),
                    h("Library/Caches/org.swift.swiftpm"),
                    h("Library/Caches/com.apple.dt.instruments"),
                ])
            ),
            Rule(
                id: "simulator-caches",
                title: t("Simulator caches", "시뮬레이터 캐시"),
                detail: t("Caches CoreSimulator regenerates. The simulator devices themselves are left alone.", "CoreSimulator가 재생성하는 캐시입니다. 시뮬레이터 기기 자체는 건드리지 않습니다."),
                category: .xcode, safety: .safe,
                target: .contentsOf([h("Library/Developer/CoreSimulator/Caches")])
            ),
            Rule(
                id: "xcode-device-support",
                title: t("iOS/watchOS device support symbols", "iOS/watchOS 기기 심볼 지원 파일"),
                detail: t("Accumulates per OS version every time you attach a physical device. Removing them costs one regeneration, taking a few minutes, the next time that device is connected.", "실기기를 연결할 때마다 OS 버전별로 쌓입니다. 지우면 해당 기기를 다시 연결할 때 한 번 재생성됩니다(수 분 소요)."),
                category: .xcode, safety: .review,
                target: .contentsOf([
                    h("Library/Developer/Xcode/iOS DeviceSupport"),
                    h("Library/Developer/Xcode/watchOS DeviceSupport"),
                    h("Library/Developer/Xcode/tvOS DeviceSupport"),
                ])
            ),
            Rule(
                id: "xcode-device-logs",
                title: t("Xcode device logs and crash reports", "Xcode 기기 로그 / 크래시 리포트"),
                detail: t("Logs collected from devices you have connected.", "연결했던 기기에서 수집한 로그입니다."),
                category: .xcode, safety: .review,
                target: .contentsOf([h("Library/Developer/Xcode/iOS Device Logs")])
            ),
            Rule(
                id: "xcode-archives",
                title: t("Xcode archives", "Xcode 아카이브"),
                detail: t("Archives and dSYMs from builds you shipped. You may still need these to symbolicate crashes from released versions, so review before deleting.", "배포한 빌드의 아카이브와 dSYM입니다. 이미 출시한 버전의 크래시 심볼리케이션에 필요할 수 있으니 확인 후 지우세요."),
                category: .xcode, safety: .caution,
                target: .contentsOf([h("Library/Developer/Xcode/Archives")])
            ),
            Rule(
                id: "simulator-devices",
                title: t("Simulator device data", "시뮬레이터 기기 데이터"),
                detail: t("Disk images for installed simulator devices, app data included. Prefer the simctl cleanup action below over deleting these one by one.", "설치된 시뮬레이터 기기의 디스크 이미지입니다. 앱 데이터가 들어 있습니다. 개별 삭제보다 아래 'simctl 정리' 작업을 먼저 쓰세요."),
                category: .xcode, safety: .caution,
                target: .paths([h("Library/Developer/CoreSimulator/Devices")])
            ),
        ]
    }

    // MARK: - Package managers / language toolchains

    static func packageManagers() -> [Rule] {
        [
            Rule(
                id: "npm-cache",
                title: t("npm cache", "npm 캐시"),
                detail: t("Tarballs npm downloaded. Refetched on reinstall.", "npm이 내려받은 tarball 캐시입니다. 재설치 시 다시 받습니다."),
                category: .packageManager, safety: .safe,
                target: .contentsOf([h(".npm/_cacache")])
            ),
            Rule(
                id: "yarn-cache",
                title: t("Yarn cache", "Yarn 캐시"),
                detail: t("Yarn's package cache.", "Yarn 패키지 캐시입니다."),
                category: .packageManager, safety: .safe,
                target: .contentsOf([h("Library/Caches/Yarn"), h(".cache/yarn"), h(".yarn/cache")])
            ),
            Rule(
                id: "bun-cache",
                title: t("Bun cache", "Bun 캐시"),
                detail: t("Bun's install cache.", "Bun 설치 캐시입니다."),
                category: .packageManager, safety: .safe,
                target: .contentsOf([h(".bun/install/cache")])
            ),
            Rule(
                id: "pnpm-store",
                title: t("pnpm content store", "pnpm 콘텐츠 저장소"),
                detail: t("pnpm hard-links node_modules into this store. Existing projects keep working after removal, but no space is actually returned while links still point at the content.", "pnpm은 node_modules를 이 저장소로 하드링크합니다. 지워도 기존 프로젝트는 계속 동작하지만, 링크가 남아 있는 만큼은 실제 공간이 회수되지 않습니다."),
                category: .packageManager, safety: .review,
                target: .contentsOf([h("Library/pnpm/store"), h(".pnpm-store"), h(".local/share/pnpm/store")])
            ),
            Rule(
                id: "homebrew-cache",
                title: t("Homebrew download cache", "Homebrew 다운로드 캐시"),
                detail: t("Bottle files used during installation. Installed packages are unaffected.", "설치에 쓰인 병(bottle) 파일들입니다. 설치된 패키지에는 영향이 없습니다."),
                category: .packageManager, safety: .safe,
                target: .contentsOf([h("Library/Caches/Homebrew")])
            ),
            Rule(
                id: "pip-cache",
                title: t("pip and uv caches", "pip / uv 캐시"),
                detail: t("Python wheel caches. Refetched on reinstall.", "Python 휠 캐시입니다. 재설치 시 다시 받습니다."),
                category: .packageManager, safety: .safe,
                target: .contentsOf([
                    h("Library/Caches/pip"), h(".cache/pip"),
                    h("Library/Caches/uv"), h(".cache/uv"),
                ])
            ),
            Rule(
                id: "go-build-cache",
                title: t("Go build cache", "Go 빌드 캐시"),
                detail: t("Go's compile cache. The next build is slower once.", "Go 컴파일 캐시입니다. 다음 빌드가 한 번 느려집니다."),
                category: .packageManager, safety: .safe,
                target: .contentsOf([h("Library/Caches/go-build")])
            ),
            Rule(
                id: "go-mod-cache",
                title: t("Go module cache", "Go 모듈 캐시"),
                detail: t("Downloaded dependency sources. Re-downloadable, but it needs a network.", "내려받은 의존성 소스입니다. 재다운로드가 가능하지만 네트워크가 필요합니다."),
                category: .packageManager, safety: .review,
                target: .contentsOf([h("go/pkg/mod/cache/download")])
            ),
            Rule(
                id: "cargo-cache",
                title: t("Cargo registry cache", "Cargo 레지스트리 캐시"),
                detail: t("Archives and unpacked sources from crates.io. Re-downloadable.", "crates.io에서 받은 압축본과 풀린 소스입니다. 재다운로드 가능합니다."),
                category: .packageManager, safety: .safe,
                target: .contentsOf([h(".cargo/registry/cache"), h(".cargo/registry/src")])
            ),
            Rule(
                id: "gradle-cache",
                title: t("Gradle caches", "Gradle 캐시"),
                detail: t("Gradle build and dependency caches.", "Gradle 빌드/의존성 캐시입니다."),
                category: .packageManager, safety: .safe,
                target: .contentsOf([h(".gradle/caches"), h(".gradle/daemon")])
            ),
            Rule(
                id: "maven-repo",
                title: t("Maven local repository", "Maven 로컬 저장소"),
                detail: t("Downloaded JARs. These may include artifacts that only ever existed on an internal repository, so review before deleting.", "내려받은 JAR입니다. 사내 저장소에만 있던 아티팩트가 섞여 있을 수 있으니 확인 후 지우세요."),
                category: .packageManager, safety: .review,
                target: .contentsOf([h(".m2/repository")])
            ),
            Rule(
                id: "cocoapods-cache",
                title: t("CocoaPods cache", "CocoaPods 캐시"),
                detail: t("Pod download cache.", "Pod 다운로드 캐시입니다."),
                category: .packageManager, safety: .safe,
                target: .contentsOf([h("Library/Caches/CocoaPods")])
            ),
            Rule(
                id: "composer-cache",
                title: t("Composer cache", "Composer 캐시"),
                detail: t("PHP Composer download cache.", "PHP Composer 다운로드 캐시입니다."),
                category: .packageManager, safety: .safe,
                target: .contentsOf([h(".composer/cache"), h(".cache/composer")])
            ),
            Rule(
                id: "deno-cache",
                title: t("Deno cache", "Deno 캐시"),
                detail: t("Deno module cache.", "Deno 모듈 캐시입니다."),
                category: .packageManager, safety: .safe,
                target: .contentsOf([h("Library/Caches/deno")])
            ),
            Rule(
                id: "electron-cache",
                title: t("Electron distribution cache", "Electron 배포본 캐시"),
                detail: t("Runtime archives fetched by electron and electron-builder.", "electron / electron-builder가 받아둔 런타임 아카이브입니다."),
                category: .packageManager, safety: .safe,
                target: .contentsOf([
                    h("Library/Caches/electron"),
                    h("Library/Caches/electron-builder"),
                    h(".electron"), h(".electron-gyp"),
                ])
            ),
            Rule(
                id: "browser-binaries",
                title: t("Playwright and Puppeteer browsers", "Playwright / Puppeteer 브라우저"),
                detail: t("Browser binaries downloaded for tests. Removing them means the next test run has to fetch them again.", "테스트용으로 받아둔 브라우저 바이너리입니다. 지우면 다음 테스트 실행 전에 다시 받아야 합니다."),
                category: .packageManager, safety: .review,
                target: .contentsOf([h("Library/Caches/ms-playwright"), h(".cache/puppeteer")])
            ),
        ]
    }

    // MARK: - Applications

    static func apps() -> [Rule] {
        [
            Rule(
                id: "vscode-cache",
                title: t("VS Code and Cursor caches", "VS Code / Cursor 캐시"),
                detail: t("Caches and logs the editor regenerates. Settings and extensions are untouched.", "에디터가 재생성하는 캐시와 로그입니다. 설정과 확장은 건드리지 않습니다."),
                category: .apps, safety: .safe,
                target: .paths([
                    h("Library/Application Support/Code/Cache"),
                    h("Library/Application Support/Code/CachedData"),
                    h("Library/Application Support/Code/CachedExtensionVSIXs"),
                    h("Library/Application Support/Code/Code Cache"),
                    h("Library/Application Support/Code/GPUCache"),
                    h("Library/Application Support/Code/logs"),
                    h("Library/Application Support/Cursor/Cache"),
                    h("Library/Application Support/Cursor/CachedData"),
                    h("Library/Application Support/Cursor/Code Cache"),
                    h("Library/Application Support/Cursor/GPUCache"),
                    h("Library/Application Support/Cursor/logs"),
                ])
            ),
            Rule(
                id: "jetbrains-cache",
                title: t("JetBrains IDE caches and logs", "JetBrains IDE 캐시 / 로그"),
                detail: t("Index caches and logs for IntelliJ-family IDEs. Removing them triggers one project re-index.", "IntelliJ 계열 IDE의 인덱스 캐시와 로그입니다. 지우면 프로젝트 재인덱싱이 한 번 일어납니다."),
                category: .apps, safety: .safe,
                target: .contentsOf([h("Library/Caches/JetBrains"), h("Library/Logs/JetBrains")])
            ),
            Rule(
                id: "app-electron-caches",
                title: t("Per-app Electron caches (bulk)", "앱별 Electron 캐시 (일괄)"),
                detail: t("Cache, Code Cache and GPUCache directories each app created under Application Support. Sign-in state and settings are stored elsewhere and are unaffected.", "Application Support 아래 각 앱이 만든 Cache / Code Cache / GPUCache 디렉터리입니다. 로그인 상태나 설정은 다른 곳에 저장되므로 영향이 없습니다."),
                category: .apps, safety: .safe,
                target: .grandchildren(
                    of: [h("Library/Application Support")],
                    named: ["Cache", "Code Cache", "GPUCache", "ShaderCache", "DawnCache", "DawnWebGPUCache", "component_crx_cache"]
                )
            ),
            Rule(
                id: "container-caches",
                title: t("Sandboxed app caches (bulk)", "샌드박스 앱 캐시 (일괄)"),
                detail: t("Caches that App Store-style sandboxed apps created inside their own containers.", "App Store 계열 샌드박스 앱들이 자기 컨테이너 안에 만든 캐시입니다."),
                category: .containers, safety: .safe,
                target: .grandchildren(
                    of: [h("Library/Containers")],
                    named: ["Data/Library/Caches"]
                )
            ),
            Rule(
                id: "docker-disk-image",
                title: t("Docker disk image", "Docker 디스크 이미지"),
                detail: t("Docker Desktop's entire virtual disk. Deleting it removes every image, container and volume; they can be pulled again. Stop the daemon first, and reach for this only when action-docker-prune was not enough.", "Docker Desktop의 가상 디스크 전체입니다. 지우면 모든 이미지·컨테이너·볼륨이 사라집니다(다시 pull 하면 복구). 데몬을 먼저 끄고, 'action-docker-prune' 으로 부족할 때만 쓰세요."),
                category: .containers, safety: .caution,
                target: .paths([
                    h("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"),
                ])
            ),
            Rule(
                id: "ios-backups",
                title: t("iPhone and iPad backups", "iPhone / iPad 백업"),
                detail: t("Full device backups. This is user data itself, so delete it only after confirming an iCloud backup exists.", "기기 전체 백업입니다. 사용자 데이터 그 자체이므로, iCloud 백업이 있는지 확인한 뒤에만 지우세요."),
                category: .userFiles, safety: .caution,
                target: .contentsOf([h("Library/Application Support/MobileSync/Backup")])
            ),
            Rule(
                id: "mail-downloads",
                title: t("Mail attachment cache", "메일 첨부파일 캐시"),
                detail: t("Temporary copies of attachments you opened. The original messages stay on the server and in your mailbox.", "메일에서 열어본 첨부파일의 임시 사본입니다. 원본 메일은 서버/메일함에 그대로 있습니다."),
                category: .userFiles, safety: .review,
                target: .contentsOf([
                    h("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")
                ])
            ),
        ]
    }

    // MARK: - Browsers

    static func browsers() -> [Rule] {
        [
            Rule(
                id: "chrome-cache",
                title: t("Chrome, Edge and Brave caches", "Chrome / Edge / Brave 캐시"),
                detail: t("Caches the browser regenerates. History, cookies and passwords are untouched.", "브라우저가 재생성하는 캐시입니다. 히스토리·쿠키·비밀번호는 건드리지 않습니다."),
                category: .browsers, safety: .safe,
                target: .contentsOf([
                    h("Library/Caches/Google/Chrome"),
                    h("Library/Caches/com.google.Chrome"),
                    h("Library/Caches/Microsoft Edge"),
                    h("Library/Caches/BraveSoftware"),
                    h("Library/Caches/com.brave.Browser"),
                ])
            ),
            Rule(
                id: "safari-cache",
                title: t("Safari cache", "Safari 캐시"),
                detail: t("Safari's web cache. Browsing history and passwords are untouched.", "Safari의 웹 캐시입니다. 방문 기록과 암호는 건드리지 않습니다."),
                category: .browsers, safety: .safe,
                target: .contentsOf([
                    h("Library/Containers/com.apple.Safari/Data/Library/Caches"),
                    h("Library/Caches/com.apple.Safari"),
                ])
            ),
            Rule(
                id: "firefox-cache",
                title: t("Firefox cache", "Firefox 캐시"),
                detail: t("Firefox's web cache.", "Firefox 웹 캐시입니다."),
                category: .browsers, safety: .safe,
                target: .contentsOf([h("Library/Caches/Firefox"), h("Library/Caches/Mozilla")])
            ),
        ]
    }

    // MARK: - Generic sweeps (must stay last among file rules)

    static func genericCaches() -> [Rule] {
        [
            Rule(
                id: "user-caches",
                title: t("Other user caches", "그 밖의 사용자 캐시"),
                detail: t("Entries in ~/Library/Caches not claimed by a more specific rule above. By definition, data the owning app can rebuild.", "위 규칙에 해당하지 않는 ~/Library/Caches 항목입니다. 정의상 앱이 다시 만들 수 있는 데이터입니다."),
                category: .systemCache, safety: .safe,
                target: .contentsOf([h("Library/Caches")])
            ),
            Rule(
                id: "user-logs",
                title: t("User logs", "사용자 로그"),
                detail: t("App logs and diagnostic files under ~/Library/Logs.", "~/Library/Logs 아래 앱 로그와 진단 파일입니다."),
                category: .logs, safety: .safe,
                target: .contentsOf([h("Library/Logs")])
            ),
            Rule(
                id: "crash-reports",
                title: t("Diagnostic reports", "진단 리포트"),
                detail: t("App crash reports and spin reports.", "앱 크래시 리포트와 스핀 리포트입니다."),
                category: .logs, safety: .safe,
                target: .contentsOf([
                    h("Library/Logs/DiagnosticReports"),
                    h("Library/Application Support/CrashReporter"),
                ])
            ),
            Rule(
                id: "saved-app-state",
                title: t("Saved application state", "저장된 앱 상태"),
                detail: t("Data used to restore window layout when an app reopens. Removing it resets window positions and nothing else.", "앱을 다시 열 때 창 배치를 복원하는 데이터입니다. 지우면 창 위치만 초기화됩니다."),
                category: .systemCache, safety: .review,
                target: .contentsOf([h("Library/Saved Application State")])
            ),
        ]
    }

    // MARK: - User files

    static func userFiles() -> [Rule] {
        [
            Rule(
                id: "downloads-installers",
                title: t("Old installers in Downloads", "오래된 설치 파일 (다운로드 폴더)"),
                detail: t("Files ending in .dmg, .pkg or .iso untouched for more than 30 days, usually left over from an install you already finished.", "30일 넘게 손대지 않은 .dmg / .pkg / .iso 파일입니다. 대개 설치를 마친 뒤 남은 것들입니다."),
                category: .userFiles, safety: .review,
                target: .olderThan(
                    dirs: [h("Downloads")],
                    days: 30,
                    extensions: ["dmg", "pkg", "iso", "xip"]
                )
            ),
            Rule(
                id: "downloads-old",
                title: t("Old downloads (90+ days)", "오래된 다운로드 (90일 이상)"),
                detail: t("Items in Downloads untouched for more than 90 days. Check the contents yourself.", "90일 넘게 손대지 않은 다운로드 폴더 항목입니다. 내용은 직접 확인하세요."),
                category: .userFiles, safety: .caution,
                target: .olderThan(dirs: [h("Downloads")], days: 90, extensions: nil)
            ),
            Rule(
                id: "trash",
                title: t("Trash", "휴지통"),
                detail: t("Files you already discarded. Emptying this is what actually reclaims the space for anything moved to the Trash.", "이미 버린 파일들입니다. 이걸 비워야 휴지통으로 옮긴 항목의 공간이 실제로 회수됩니다."),
                category: .userFiles, safety: .review,
                target: .contentsOf([h(".Trash")])
            ),
        ]
    }

    // MARK: - Delegated actions

    static func actions() -> [Rule] {
        [
            Rule(
                id: "action-tm-snapshots",
                title: t("Thin Time Machine local snapshots", "Time Machine 로컬 스냅샷 정리"),
                detail: t("APFS local snapshots are the most common reason space does not show up as available. This hands the job to tmutil instead of deleting anything directly.", "APFS 로컬 스냅샷은 '사용 가능' 용량에 잡히지 않는 공간을 붙들고 있는 가장 흔한 원인입니다. tmutil이 직접 정리하도록 맡깁니다."),
                category: .systemCache, safety: .review,
                target: .action(ActionSpec(
                    requires: "tmutil",
                    probe: ["tmutil", "listlocalsnapshots", "/"],
                    estimator: .timeMachineSnapshots,
                    // Target 20GB, urgency 4 (most aggressive).
                    execute: ["tmutil", "thinlocalsnapshots", "/", "21474836480", "4"]
                ))
            ),
            Rule(
                id: "action-simctl-unavailable",
                title: t("Delete unavailable simulator devices", "사용 불가 시뮬레이터 기기 삭제"),
                detail: t("Removes simulator devices already unusable because their runtime is not installed. Usable devices are left alone.", "설치되지 않은 런타임에 묶여 이미 못 쓰는 시뮬레이터 기기를 지웁니다. 쓸 수 있는 기기는 그대로 둡니다."),
                category: .xcode, safety: .safe,
                target: .action(ActionSpec(
                    requires: "xcrun",
                    probe: ["xcrun", "simctl", "list", "devices", "--json"],
                    estimator: .simctlUnavailable,
                    execute: ["xcrun", "simctl", "delete", "unavailable"]
                ))
            ),
            Rule(
                id: "action-brew-cleanup",
                title: t("Homebrew cleanup", "Homebrew 정리"),
                detail: t("Lets Homebrew itself remove old formula versions and leftover downloads.", "구버전 포뮬러와 남은 다운로드를 Homebrew가 직접 정리합니다."),
                category: .packageManager, safety: .safe,
                target: .action(ActionSpec(
                    requires: "brew",
                    probe: ["brew", "cleanup", "--dry-run"],
                    estimator: .brewCleanupDryRun,
                    execute: ["brew", "cleanup", "--prune=all"]
                ))
            ),
            Rule(
                id: "action-docker-prune",
                title: t("Prune unused Docker resources", "Docker 미사용 리소스 정리"),
                detail: t("Removes images, build cache and volumes that no container references. Anything used by a running or stopped container stays.", "어떤 컨테이너도 참조하지 않는 이미지·빌드 캐시·볼륨을 지웁니다. 실행 중이거나 정지된 컨테이너가 쓰는 것은 남습니다."),
                category: .containers, safety: .review,
                target: .action(ActionSpec(
                    requires: "docker",
                    probe: ["docker", "system", "df", "--format", "{{.Type}}\t{{.Reclaimable}}"],
                    estimator: .dockerSystemDF,
                    execute: ["docker", "system", "prune", "-a", "-f"]
                ))
            ),
        ]
    }

    // MARK: - Deep project scan (--deep only)

    static func deepProjects() -> [Rule] {
        [
            Rule(
                id: "project-node-modules",
                title: t("Stale node_modules", "오래된 node_modules"),
                detail: t("node_modules in projects untouched for more than 60 days. One npm install restores them.", "60일 넘게 손대지 않은 프로젝트의 node_modules입니다. `npm install` 한 번으로 복구됩니다."),
                category: .projects, safety: .caution,
                target: .projectArtifacts(names: ["node_modules"], idleDays: 60),
                deep: true
            ),
            Rule(
                id: "project-build-dirs",
                title: t("Stale build output directories", "오래된 빌드 산출물 디렉터리"),
                detail: t("Build output directories in projects untouched for more than 60 days. Rebuilding restores them.", "60일 넘게 손대지 않은 프로젝트의 빌드 출력 디렉터리입니다. 다시 빌드하면 복구됩니다."),
                category: .projects, safety: .caution,
                target: .projectArtifacts(
                    names: ["target", "build", "dist", ".next", ".nuxt", ".turbo", ".gradle", "DerivedData", ".build"],
                    idleDays: 60
                ),
                deep: true
            ),
        ]
    }
}
