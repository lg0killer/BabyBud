"""Generate the dependency-free iOS project. Run with Python 3 from any directory."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "BabyBuddy.xcodeproj"


def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def generate():
    sources = sorted([*ROOT.glob("Sources/BabyBuddyCore/*.swift"), *ROOT.glob("iOS/*.swift")])
    objects = []

    def add(name, value):
        objects.append(f"\t\t{uid(name)} = {{ {value} }};")
        return uid(name)

    refs, builds = [], []
    for file in sources:
        path = file.relative_to(ROOT).as_posix()
        ref = add(path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path}"; sourceTree = SOURCE_ROOT;')
        refs.append(ref)
        builds.append(add(path + ":build", f"isa = PBXBuildFile; fileRef = {ref};"))

    config_ref = add("config", 'isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = "Config/Development.xcconfig"; sourceTree = SOURCE_ROOT;')
    refs.append(config_ref)
    assets_ref = add("assets", 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "iOS/Assets.xcassets"; sourceTree = SOURCE_ROOT;')
    refs.append(assets_ref)
    assets_build = add("assets-build", f'isa = PBXBuildFile; fileRef = {assets_ref};')
    test_ref = add("ui-test-source", 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "UITests/BabyBuddyUITests.swift"; sourceTree = SOURCE_ROOT;')
    refs.append(test_ref)
    test_build = add("ui-test-build", f'isa = PBXBuildFile; fileRef = {test_ref};')
    test_product = add("ui-test-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = BabyBuddyUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    product = add("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = BabyBuddy.app; sourceTree = BUILT_PRODUCTS_DIR;')
    products = add("products", f'isa = PBXGroup; name = Products; children = ({product},{test_product},); sourceTree = "<group>";')
    group = add("main", f'isa = PBXGroup; children = ({",".join(refs + [products])},); sourceTree = "<group>";')
    sources_phase = add("sources", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
    frameworks = add("frameworks", 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    resources = add("resources", f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({assets_build},); runOnlyForDeploymentPostprocessing = 0;')
    project_configs, target_configs = [], []
    for config in ("Debug", "Release"):
        project_configs.append(add(f"project:{config}", f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; }};'))
        debug = 'SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if config == "Debug" else 'SWIFT_COMPILATION_MODE = wholemodule; SWIFT_OPTIMIZATION_LEVEL = "-O";'
        target_configs.append(add(f"target:{config}", f'''isa = XCBuildConfiguration; name = {config}; baseConfigurationReference = {config_ref}; buildSettings = {{
            PRODUCT_NAME = "$(TARGET_NAME)";
            PRODUCT_BUNDLE_IDENTIFIER = "$(BABYBUDDY_BUNDLE_IDENTIFIER)";
            CODE_SIGN_ENTITLEMENTS = "$(BABYBUDDY_ENTITLEMENTS)";
            "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]" = "$(BABYBUDDY_MAC_ENTITLEMENTS)";
            CODE_SIGN_STYLE = Automatic;
            GENERATE_INFOPLIST_FILE = YES;
            ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
            INFOPLIST_FILE = iOS/Info.plist;
            INFOPLIST_KEY_CFBundleDisplayName = "Baby Buddy";
            INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.lifestyle";
            INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
            INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
            INFOPLIST_KEY_UILaunchScreen_Generation = YES;
            INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
            INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
            TARGETED_DEVICE_FAMILY = "1,2";
            SUPPORTS_MACCATALYST = YES;
            SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
            MARKETING_VERSION = 0.1.1;
            CURRENT_PROJECT_VERSION = 2;
            {debug}
        }};'''))
    project_config_list = add("project-configs", f'isa = XCConfigurationList; buildConfigurations = ({",".join(project_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    target_config_list = add("target-configs", f'isa = XCConfigurationList; buildConfigurations = ({",".join(target_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    target = add("target", f'isa = PBXNativeTarget; buildConfigurationList = {target_config_list}; buildPhases = ({sources_phase},{frameworks},{resources},); buildRules = (); dependencies = (); name = BabyBuddy; productName = BabyBuddy; productReference = {product}; productType = "com.apple.product-type.application";')
    test_sources = add("ui-test-sources", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({test_build},); runOnlyForDeploymentPostprocessing = 0;')
    test_configs = []
    for config in ("Debug", "Release"):
        test_configs.append(add(f"ui-test:{config}", f'''isa = XCBuildConfiguration; name = {config}; baseConfigurationReference = {config_ref}; buildSettings = {{
            PRODUCT_NAME = "$(TARGET_NAME)";
            PRODUCT_BUNDLE_IDENTIFIER = "$(BABYBUDDY_BUNDLE_IDENTIFIER).UITests";
            CODE_SIGN_STYLE = Automatic;
            GENERATE_INFOPLIST_FILE = YES;
            TEST_TARGET_NAME = BabyBuddy;
            TARGETED_DEVICE_FAMILY = "1,2";
            SUPPORTS_MACCATALYST = YES;
            SWIFT_OPTIMIZATION_LEVEL = "-Onone";
        }};'''))
    test_config_list = add("ui-test-configs", f'isa = XCConfigurationList; buildConfigurations = ({",".join(test_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    proxy = add("ui-test-proxy", f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = BabyBuddy;')
    dependency = add("ui-test-dependency", f'isa = PBXTargetDependency; target = {target}; targetProxy = {proxy};')
    test_target = add("ui-test-target", f'isa = PBXNativeTarget; buildConfigurationList = {test_config_list}; buildPhases = ({test_sources},); buildRules = (); dependencies = ({dependency},); name = BabyBuddyUITests; productName = BabyBuddyUITests; productReference = {test_product}; productType = "com.apple.product-type.bundle.ui-testing";')
    project = add("project", f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {project_config_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base,); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},{test_target},);')
    PROJECT.mkdir(exist_ok=True)
    (PROJECT / "project.pbxproj").write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {project};\n}}\n', encoding="utf-8")
    schemes = PROJECT / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    buildable = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="BabyBuddy.app" BlueprintName="BabyBuddy" ReferencedContainer="container:BabyBuddy.xcodeproj"/>'
    test_buildable = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="BabyBuddyUITests.xctest" BlueprintName="BabyBuddyUITests" ReferencedContainer="container:BabyBuddy.xcodeproj"/>'
    (schemes / "BabyBuddy.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_buildable}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''', encoding="utf-8")
    print(f"Generated {PROJECT.name} with {len(sources)} Swift sources")


if __name__ == "__main__":
    generate()
