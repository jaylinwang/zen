#!/usr/bin/env python3
"""Generate a dependency-free Xcode project for the shared Swift package and native app targets."""
import hashlib
from pathlib import Path
root = Path(__file__).resolve().parent.parent
objects = {}
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(name, content):
    key = uid(name); objects[key] = content; return key
source = add('source', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Sources/ZenApp/ZenApp.swift; sourceTree = SOURCE_ROOT;')
package = add('package', 'isa = XCLocalSwiftPackageReference; relativePath = ".";')
products=[]; targets=[]
for platform in ['macOS', 'iOS']:
    name = 'Zen-' + platform
    product = add(name+'product', f'isa = PBXFileReference; explicitFileType = wrapper.application; path = "{name}.app"; sourceTree = BUILT_PRODUCTS_DIR;'); products.append(product)
    sourcebuild = add(name+'sourcebuild', f'isa = PBXBuildFile; fileRef = {source};')
    sources = add(name+'sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({sourcebuild},); runOnlyForDeploymentPostprocessing = 0;')
    deps=[]; links=[]
    for library in ['ZenCore','ZenUI']:
        dep = add(name+library, f'isa = XCSwiftPackageProductDependency; package = {package}; productName = {library};'); deps.append(dep)
        links.append(add(name+library+'link', f'isa = PBXBuildFile; productRef = {dep};'))
    frameworks = add(name+'frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({",".join(links)},); runOnlyForDeploymentPostprocessing = 0;')
    configs=[]
    for configuration in ['Debug','Release']:
        settings = {
            'PRODUCT_NAME': name, 'PRODUCT_BUNDLE_IDENTIFIER': 'personal.zen.'+('mac' if platform=='macOS' else 'ios'),
            'SWIFT_VERSION': '5.0', 'CODE_SIGN_STYLE': 'Automatic', 'MARKETING_VERSION': '0.1.0', 'CURRENT_PROJECT_VERSION': '1',
            'GENERATE_INFOPLIST_FILE': 'YES', 'INFOPLIST_KEY_CFBundleDisplayName': '禅',
            'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if configuration=='Debug' else '-O',
            'SDKROOT': 'macosx' if platform=='macOS' else 'iphoneos',
            'ENABLE_USER_SCRIPT_SANDBOXING': 'YES'
        }
        if platform == 'macOS':
            settings.update(MACOSX_DEPLOYMENT_TARGET='13.0', CODE_SIGN_ENTITLEMENTS='Platform/macOS.entitlements',
                            INFOPLIST_KEY_LSApplicationCategoryType='public.app-category.productivity')
        else:
            settings.update(IPHONEOS_DEPLOYMENT_TARGET='16.0', TARGETED_DEVICE_FAMILY='1',
                            SUPPORTED_PLATFORMS='iphoneos iphonesimulator', SUPPORTS_MACCATALYST='NO',
                            GENERATE_INFOPLIST_FILE='NO', INFOPLIST_FILE='Platform/iOS-Info.plist')
        body=' '.join(f'{k} = "{v}";' for k,v in settings.items())
        configs.append(add(name+configuration, f'isa = XCBuildConfiguration; name = {configuration}; buildSettings = {{{body}}};'))
    configlist = add(name+'configlist', f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    target=add(name, f'isa = PBXNativeTarget; name = "{name}"; productName = "{name}"; productReference = {product}; productType = "com.apple.product-type.application"; buildConfigurationList = {configlist}; buildPhases = ({sources},{frameworks},); buildRules = (); dependencies = (); packageProductDependencies = ({",".join(deps)},);')
    targets.append(target)
    schemes = root/'Zen.xcodeproj/xcshareddata/xcschemes'; schemes.mkdir(parents=True,exist_ok=True)
    reference=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}.app" BlueprintName="{name}" ReferencedContainer="container:Zen.xcodeproj"/>'
    (schemes/(name+'.xcscheme')).write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
# Native UI tests run the installed iPhone app, including the system folder picker.
uitestname = 'Zen-iOSUITests'
uitestsource = add('uitestsource', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Tests/ZenUITests/ZenUITests.swift; sourceTree = SOURCE_ROOT;')
uitestproduct = add('uitestproduct', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = "Zen-iOSUITests.xctest"; sourceTree = BUILT_PRODUCTS_DIR;')
products.append(uitestproduct)
uitestbuild = add('uitestbuild', f'isa = PBXBuildFile; fileRef = {uitestsource};')
uitestsources = add('uitestsources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({uitestbuild},); runOnlyForDeploymentPostprocessing = 0;')
uitestframeworks = add('uitestframeworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
uitestdependency = add('uitestdependency', f'isa = PBXTargetDependency; target = {uid("Zen-iOS")};')
uitestconfigs = []
for config in ['Debug', 'Release']:
    uitestconfigs.append(add('uitest'+config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{PRODUCT_NAME = "{uitestname}"; PRODUCT_BUNDLE_IDENTIFIER = "personal.zen.ios.uitests"; SWIFT_VERSION = "5.0"; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = "16.0"; TARGETED_DEVICE_FAMILY = "1"; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; GENERATE_INFOPLIST_FILE = YES; TEST_TARGET_NAME = "Zen-iOS"; CODE_SIGN_STYLE = Automatic;}};'))
uitestconfiglist = add('uitestconfiglist', f'isa = XCConfigurationList; buildConfigurations = ({",".join(uitestconfigs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
uitesttarget = add('uitesttarget', f'isa = PBXNativeTarget; name = "{uitestname}"; productName = "{uitestname}"; productReference = {uitestproduct}; productType = "com.apple.product-type.bundle.ui-testing"; buildConfigurationList = {uitestconfiglist}; buildPhases = ({uitestsources},{uitestframeworks},); buildRules = (); dependencies = ({uitestdependency},);')
targets.append(uitesttarget)
scheme = root/'Zen.xcodeproj/xcshareddata/xcschemes/Zen-iOS.xcscheme'
uitestref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uitesttarget}" BuildableName="{uitestname}.xctest" BlueprintName="{uitestname}" ReferencedContainer="container:Zen.xcodeproj"/>'
schemetext = scheme.read_text().replace('</BuildActionEntries>', f'<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{uitestref}</BuildActionEntry></BuildActionEntries>')
schemetext = schemetext.replace('<LaunchAction ', f'<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{uitestref}</TestableReference></Testables></TestAction><LaunchAction ')
scheme.write_text(schemetext)
prodgroup=add('products', f'isa = PBXGroup; name = Products; sourceTree = "<group>"; children = ({",".join(products)},);')
group=add('main', f'isa = PBXGroup; sourceTree = "<group>"; children = ({source},{uitestsource},{prodgroup},);')
configs=[]
for config in ['Debug','Release']:
    configs.append(add('project'+config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{CLANG_ENABLE_MODULES = YES; SWIFT_STRICT_CONCURRENCY = targeted; ONLY_ACTIVE_ARCH = {"YES" if config == "Debug" else "NO"};}};'))
configlist=add('projectconfigs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
project=add('project', f'isa = PBXProject; attributes = {{LastUpgradeCheck = 1600;}}; buildConfigurationList = {configlist}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = (en, "zh-Hans", Base,); mainGroup = {group}; productRefGroup = {prodgroup}; projectDirPath = ""; projectRoot = ""; targets = ({",".join(targets)},); packageReferences = ({package},);')
(root/'Zen.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(f'{key} = {{{value}}};' for key,value in objects.items())+f'\n}}; rootObject = {project};}}\n')
print('Generated Zen.xcodeproj (macOS + iOS)')
