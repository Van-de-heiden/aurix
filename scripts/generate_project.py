#!/usr/bin/env python3
"""Generate the checked-in Xcode project using only Python's standard library."""
from pathlib import Path
import hashlib
import json
import plistlib

ROOT = Path(__file__).resolve().parents[1]
objects = {}

def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def obj(token, isa, **attrs):
    key = ident(token)
    objects[key] = dict(isa=isa, **attrs)
    return key

def file(path, kind):
    return obj('file:'+path, 'PBXFileReference', lastKnownFileType=kind, path=path, sourceTree='<group>')

def phase(name, isa, files):
    return obj(name, isa, buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0)

def configurations(name, values):
    configs = []
    for mode in ['Debug', 'Release']:
        settings = values.copy()
        settings.update(SWIFT_OPTIMIZATION_LEVEL='-Onone' if mode == 'Debug' else '-O',
                        DEBUG_INFORMATION_FORMAT='dwarf' if mode == 'Debug' else 'dwarf-with-dsym')
        if mode == 'Debug': settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG $(inherited)'
        configs.append(obj(name+mode, 'XCBuildConfiguration', buildSettings=settings, name=mode))
    return obj(name+'configs', 'XCConfigurationList', buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName='Release')

source_refs, builds = [], []
for source in sorted((ROOT/'Aurix').rglob('*.swift')):
    rel = str(source.relative_to(ROOT))
    ref = file(rel, 'sourcecode.swift'); source_refs.append(ref)
    builds.append(obj('build:'+rel, 'PBXBuildFile', fileRef=ref))
assets = file('Aurix/Resources/Assets.xcassets', 'folder.assetcatalog')
privacy = file('Aurix/Resources/PrivacyInfo.xcprivacy', 'text.xml')
info = file('Aurix/Resources/Info.plist', 'text.plist.xml')
appProduct = obj('app-product', 'PBXFileReference', explicitFileType='wrapper.application', includeInIndex=0, path='Aurix.app', sourceTree='BUILT_PRODUCTS_DIR')
testProduct = obj('ui-product', 'PBXFileReference', explicitFileType='wrapper.cfbundle', includeInIndex=0, path='AurixUITests.xctest', sourceTree='BUILT_PRODUCTS_DIR')
products = obj('products', 'PBXGroup', children=[appProduct, testProduct], name='Products', sourceTree='<group>')
ui = file('AurixUITests/AurixUITests.swift', 'sourcecode.swift')
group = obj('main-group', 'PBXGroup', children=source_refs+[assets, privacy, info, ui, products], sourceTree='<group>')
package = obj('core-package', 'XCLocalSwiftPackageReference', relativePath='.')
productDep = obj('core-dependency', 'XCSwiftPackageProductDependency', productName='AurixCore')
coreLink = obj('core-link', 'PBXBuildFile', productRef=productDep)

shared = dict(SWIFT_VERSION='5.0', IPHONEOS_DEPLOYMENT_TARGET='17.0', SDKROOT='iphoneos',
              TARGETED_DEVICE_FAMILY='1', SUPPORTED_PLATFORMS='iphoneos iphonesimulator',
              CODE_SIGN_STYLE='Automatic', CURRENT_PROJECT_VERSION='1', MARKETING_VERSION='1.0',
              CLANG_ENABLE_MODULES='YES', ENABLE_USER_SCRIPT_SANDBOXING='YES')
appsettings = dict(shared, PRODUCT_NAME='$(TARGET_NAME)', PRODUCT_BUNDLE_IDENTIFIER='ch.mauruspichler.aurix',
                   GENERATE_INFOPLIST_FILE='NO', INFOPLIST_FILE='Aurix/Resources/Info.plist',
                   ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon', ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME='AccentColor',
                   LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/Frameworks', SUPPORTS_MACCATALYST='NO',
                   SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD='NO', SWIFT_EMIT_LOC_STRINGS='YES')
app = obj('app-target', 'PBXNativeTarget', buildConfigurationList=configurations('app', appsettings),
          buildPhases=[phase('app-sources', 'PBXSourcesBuildPhase', builds), phase('app-frameworks', 'PBXFrameworksBuildPhase', [coreLink]),
                       phase('app-resources', 'PBXResourcesBuildPhase', [obj('asset-build','PBXBuildFile',fileRef=assets),obj('privacy-build','PBXBuildFile',fileRef=privacy)])],
          buildRules=[], dependencies=[], name='Aurix', packageProductDependencies=[productDep], productName='Aurix', productReference=appProduct,
          productType='com.apple.product-type.application')
proxy = obj('proxy', 'PBXContainerItemProxy', containerPortal=ident('project'), proxyType=1, remoteGlobalIDString=app, remoteInfo='Aurix')
dependency = obj('test-dependency', 'PBXTargetDependency', target=app, targetProxy=proxy)
test = obj('ui-target', 'PBXNativeTarget', buildConfigurationList=configurations('ui', dict(shared, PRODUCT_NAME='$(TARGET_NAME)',
           PRODUCT_BUNDLE_IDENTIFIER='ch.mauruspichler.aurix.uitests', GENERATE_INFOPLIST_FILE='YES', TEST_TARGET_NAME='Aurix')),
           buildPhases=[phase('ui-sources', 'PBXSourcesBuildPhase', [obj('ui-build','PBXBuildFile',fileRef=ui)]),phase('ui-frameworks','PBXFrameworksBuildPhase',[])],
           buildRules=[], dependencies=[dependency], name='AurixUITests', productName='AurixUITests', productReference=testProduct,
           productType='com.apple.product-type.bundle.ui-testing')
project = obj('project', 'PBXProject', attributes=dict(BuildIndependentTargetsInParallel='YES', LastUpgradeCheck='1600',
              TargetAttributes={app:dict(CreatedOnToolsVersion='16.0'),test:dict(CreatedOnToolsVersion='16.0',TestTargetID=app)}),
              buildConfigurationList=configurations('project',dict(CLANG_ENABLE_MODULES='YES',SWIFT_VERSION='5.0')),
              compatibilityVersion='Xcode 14.0', developmentRegion='de', hasScannedForEncodings=0,
              knownRegions=['de','en','Base'], mainGroup=group, packageReferences=[package], productRefGroup=products,
              projectDirPath='', projectRoot='', targets=[app,test])

def serialize(value, depth=0):
    indent='\t'*depth
    if isinstance(value, dict):
        return '{\n' + ''.join(indent+'\t'+json.dumps(str(k))+' = '+serialize(v,depth+1)+';\n' for k,v in value.items()) + indent+'}'
    if isinstance(value, list):
        return '(\n' + ''.join(indent+'\t'+serialize(v,depth+1)+',\n' for v in value) + indent+')'
    if isinstance(value, int): return str(value)
    return json.dumps(str(value), ensure_ascii=False)

projectDir=ROOT/'Aurix.xcodeproj'
projectDir.mkdir(exist_ok=True)
(projectDir/'project.pbxproj').write_text('// !$*UTF8*$!\n'+serialize(dict(archiveVersion=1,classes={},objectVersion=56,objects=objects,rootObject=project))+'\n')
schemes=projectDir/'xcshareddata/xcschemes'; schemes.mkdir(parents=True,exist_ok=True)
def reference(target, product, name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:Aurix.xcodeproj"/>'
(schemes/'Aurix.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference(app,'Aurix.app','Aurix')}</BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
  <Testables><TestableReference skipped="NO">{reference(test,'AurixUITests.xctest','AurixUITests')}</TestableReference></Testables>
 </TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app,'Aurix.app','Aurix')}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app,'Aurix.app','Aurix')}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')

infoData=dict(CFBundleDevelopmentRegion='de',CFBundleDisplayName='AURIX',CFBundleExecutable='$(EXECUTABLE_NAME)',
    CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)',CFBundleInfoDictionaryVersion='6.0',CFBundleName='$(PRODUCT_NAME)',
    CFBundlePackageType='APPL',CFBundleShortVersionString='$(MARKETING_VERSION)',CFBundleVersion='$(CURRENT_PROJECT_VERSION)',
    LSRequiresIPhoneOS=True,UILaunchScreen={},UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait'],
    UIUserInterfaceStyle='Dark',NSCameraUsageDescription='AURIX fotografiert deine Mahlzeit oder scannt einen Lebensmittel-Barcode, wenn du die Erfassung öffnest.',
    NSMicrophoneUsageDescription='Beschreibe deine Mahlzeit mit deiner Stimme. AURIX speichert keine Audiodatei.',
    NSSpeechRecognitionUsageDescription='AURIX wandelt deine Mahlzeitenbeschreibung in Text um. Falls nötig verarbeitet Apple die Aufnahme.',
    ITSAppUsesNonExemptEncryption=False)
(ROOT/'Aurix/Resources/Info.plist').write_bytes(plistlib.dumps(infoData,sort_keys=False))
privacyData=dict(NSPrivacyTracking=False,NSPrivacyTrackingDomains=[],NSPrivacyCollectedDataTypes=[],
    NSPrivacyAccessedAPITypes=[dict(NSPrivacyAccessedAPIType='NSPrivacyAccessedAPICategoryUserDefaults',NSPrivacyAccessedAPITypeReasons=['CA92.1']),
    dict(NSPrivacyAccessedAPIType='NSPrivacyAccessedAPICategoryFileTimestamp',NSPrivacyAccessedAPITypeReasons=['C617.1'])])
(ROOT/'Aurix/Resources/PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps(privacyData,sort_keys=False))
print(f'Generated Aurix.xcodeproj ({len(source_refs)} Swift app files)')
