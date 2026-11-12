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

    product = add("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = BabyBuddy.app; sourceTree = BUILT_PRODUCTS_DIR;')
    products = add("products", f'isa = PBXGroup; name = Products; children = ({product},); sourceTree = "<group>";')
    group = add("main", f'isa = PBXGroup; children = ({",".join(refs + [products])},); sourceTree = "<group>";')
    sources_phase = add("sources", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
    frameworks = add("frameworks", 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    resources = add("resources", 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    project_configs, target_configs = [], []
    for config in ("Debug", "Release"):
        project_configs.append(add(f"project:{config}", f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; }};'))
        debug = 'SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if config == "Debug" else 'SWIFT_COMPILATION_MODE = wholemodule; SWIFT_OPTIMIZATION_LEVEL = "-O";'
        target_configs.append(add(f"target:{config}", f'''isa = XCBuildConfiguration; name = {config}; buildSettings = {{
            PRODUCT_NAME = "$(TARGET_NAME)";
            PRODUCT_BUNDLE_IDENTIFIER = org.example.BabyBuddy;
            CODE_SIGN_STYLE = Automatic;
            GENERATE_INFOPLIST_FILE = YES;
            INFOPLIST_KEY_CFBundleDisplayName = "Baby Buddy";
            INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.lifestyle";
            INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
            INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
            INFOPLIST_KEY_UILaunchScreen_Generation = YES;
            INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
            TARGETED_DEVICE_FAMILY = 1;
            SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
            MARKETING_VERSION = 0.1.0;
            CURRENT_PROJECT_VERSION = 1;
            {debug}
        }};'''))
    project_config_list = add("project-configs", f'isa = XCConfigurationList; buildConfigurations = ({",".join(project_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    target_config_list = add("target-configs", f'isa = XCConfigurationList; buildConfigurations = ({",".join(target_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    target = add("target", f'isa = PBXNativeTarget; buildConfigurationList = {target_config_list}; buildPhases = ({sources_phase},{frameworks},{resources},); buildRules = (); dependencies = (); name = BabyBuddy; productName = BabyBuddy; productReference = {product}; productType = "com.apple.product-type.application";')
    project = add("project", f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {project_config_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base,); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
    PROJECT.mkdir(exist_ok=True)
    (PROJECT / "project.pbxproj").write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {project};\n}}\n', encoding="utf-8")
    schemes = PROJECT / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    buildable = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="BabyBuddy.app" BlueprintName="BabyBuddy" ReferencedContainer="container:BabyBuddy.xcodeproj"/>'
    (schemes / "BabyBuddy.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"/>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''', encoding="utf-8")
    print(f"Generated {PROJECT.name} with {len(sources)} Swift sources")


if __name__ == "__main__":
    generate()
