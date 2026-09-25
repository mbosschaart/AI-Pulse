#!/usr/bin/env python3
"""Generate a dependency-free Xcode project. Run from any directory."""
from pathlib import Path
import hashlib,json,plistlib
root=Path(__file__).resolve().parents[1]
version=json.loads((root/'Config/version.json').read_text())
objects={}
def oid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def add(identity,**fields):
 key=oid(identity);objects[key]=fields;return key

def encode(v):
 if isinstance(v,dict): return '{\n'+''.join(f'{encode(k)} = {encode(x)};\n' for k,x in v.items())+'}'
 if isinstance(v,list): return '('+','.join(encode(x) for x in v)+')'
 return json.dumps(str(v))
for name in ['openai','claude','cursor','openrouter']:
 d=root/'Resources/Assets.xcassets'/f'{name}.imageset';d.mkdir(parents=True,exist_ok=True)
 (d/f'{name}.svg').write_bytes((root/'Resources'/f'{name}.svg').read_bytes())
 (d/'Contents.json').write_text(json.dumps({'images':[{'filename':f'{name}.svg','idiom':'universal'}],'info':{'author':'xcode','version':1},'properties':{'preserves-vector-representation':True}}))
(root/'Resources/Assets.xcassets/Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
sparkle=add('sparkle',isa='PBXFileReference',lastKnownFileType='wrapper.framework',path='Vendor/Sparkle.framework',sourceTree='<group>')
refs={}
for path in sorted(list(root.glob('Shared/*.swift'))+list(root.glob('App/*.swift'))+list(root.glob('Widget/*.swift'))):
 rel=str(path.relative_to(root));refs[rel]=add(rel,isa='PBXFileReference',lastKnownFileType='sourcecode.swift',path=rel,sourceTree='<group>')
assets=add('assets',isa='PBXFileReference',lastKnownFileType='folder.assetcatalog',path='Resources/Assets.xcassets',sourceTree='<group>')
appProduct=add('appProduct',isa='PBXFileReference',explicitFileType='wrapper.application',path='AI Pulse.app',sourceTree='BUILT_PRODUCTS_DIR')
widgetProduct=add('widgetProduct',isa='PBXFileReference',explicitFileType='wrapper.app-extension',path='AIPulseWidget.appex',sourceTree='BUILT_PRODUCTS_DIR')
products=add('products',isa='PBXGroup',children=[appProduct,widgetProduct],name='Products',sourceTree='<group>')
main=add('main',isa='PBXGroup',children=list(refs.values())+[assets,sparkle,products],sourceTree='<group>')
def configs(name,settings):
 ids=[]
 for config in ['Debug','Release']:
  st=dict(settings);st['SWIFT_OPTIMIZATION_LEVEL']='-Onone' if config=='Debug' else '-O';st['DEBUG_INFORMATION_FORMAT']='dwarf'
  ids.append(add(name+config,isa='XCBuildConfiguration',buildSettings=st,name=config))
 return add(name+'configs',isa='XCConfigurationList',buildConfigurations=ids,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
common={'SDKROOT':'macosx','MACOSX_DEPLOYMENT_TARGET':'14.0','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','CODE_SIGN_STYLE':'Manual','CODE_SIGN_INJECT_BASE_ENTITLEMENTS':'NO','CODE_SIGN_IDENTITY':'Developer ID Application','DEVELOPMENT_TEAM':'EJ77LX9A8T','ENABLE_HARDENED_RUNTIME':'YES','CURRENT_PROJECT_VERSION':version['build'],'MARKETING_VERSION':version['marketing'],'GENERATE_INFOPLIST_FILE':'NO'}
projectConfigs=configs('project',common)
for target in ['app','widget']:
 files=[]
 for p,r in refs.items():
  included=(p.startswith('Shared/') and (target=='app' or p not in ['Shared/OpenAICostClient.swift','Shared/OpenRouterCostClient.swift','Shared/Parsers.swift'])) or p.startswith('App/' if target=='app' else 'Widget/')
  if included: files.append(add(target+p,isa='PBXBuildFile',fileRef=r))
 sources=add(target+'sources',isa='PBXSourcesBuildPhase',buildActionMask=2147483647,files=files,runOnlyForDeploymentPostprocessing=0)
 resource=add(target+'resources',isa='PBXResourcesBuildPhase',buildActionMask=2147483647,files=[add(target+'assets',isa='PBXBuildFile',fileRef=assets)],runOnlyForDeploymentPostprocessing=0)
 phases=[sources,resource];deps=[]
 if target=='app':
  phases.append(add('sparklelink',isa='PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[add('sparklelinked',isa='PBXBuildFile',fileRef=sparkle)],runOnlyForDeploymentPostprocessing=0))
  phases.append(add('sparkleembed',isa='PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=10,files=[add('sparkleembedded',isa='PBXBuildFile',fileRef=sparkle,settings={'ATTRIBUTES':['CodeSignOnCopy','RemoveHeadersOnCopy']})],name='Embed Sparkle',runOnlyForDeploymentPostprocessing=0))
  proxy=add('proxy',isa='PBXContainerItemProxy',containerPortal=oid('project'),proxyType=1,remoteGlobalIDString=oid('widgetTarget'),remoteInfo='AIPulseWidget')
  deps=[add('dependency',isa='PBXTargetDependency',target=oid('widgetTarget'),targetProxy=proxy)]
  embed=add('embedfile',isa='PBXBuildFile',fileRef=widgetProduct,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
  phases.append(add('embed',isa='PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[embed],name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0))
 st={'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon' if target=='app' else '', 'PRODUCT_NAME':'AI Pulse' if target=='app' else 'AIPulseWidget','PRODUCT_BUNDLE_IDENTIFIER':'nl.martijn.aipulse'+('' if target=='app' else '.widget'),'INFOPLIST_FILE':'Config/'+target+'.plist','CODE_SIGN_ENTITLEMENTS':'Config/'+target+'.entitlements','FRAMEWORK_SEARCH_PATHS':['$(inherited)','$(PROJECT_DIR)/Vendor'],'LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/../Frameworks'],'SKIP_INSTALL':'NO' if target=='app' else 'YES','APPLICATION_EXTENSION_API_ONLY':'NO' if target=='app' else 'YES'}
 add(target+'Target',isa='PBXNativeTarget',buildConfigurationList=configs(target,st),buildPhases=phases,buildRules=[],dependencies=deps,name='AIPulse' if target=='app' else 'AIPulseWidget',productName=st['PRODUCT_NAME'],productReference=appProduct if target=='app' else widgetProduct,productType='com.apple.product-type.application' if target=='app' else 'com.apple.product-type.app-extension')
add('project',isa='PBXProject',attributes={'LastUpgradeCheck':'1600','BuildIndependentTargetsInParallel':'YES'},buildConfigurationList=projectConfigs,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=main,productRefGroup=products,projectDirPath='',projectRoot='',targets=[oid('appTarget'),oid('widgetTarget')])
proj=root/'AIPulse.xcodeproj';proj.mkdir(exist_ok=True)
(proj/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':oid('project')}))
for target in ['app','widget']:
 info={'CFBundleDisplayName':'AI Pulse','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'APPL' if target=='app' else 'XPC!','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','LSMinimumSystemVersion':'$(MACOSX_DEPLOYMENT_TARGET)','AIPulseAppGroup':'$(DEVELOPMENT_TEAM).nl.martijn.aipulse'}
 if target=='app': info.update({'LSUIElement':True,'NSHumanReadableCopyright':'Designed by Martijn Bosschaart, 2026','AIPulseDisplayVersion':version['display'],'SUFeedURL':'https://raw.githubusercontent.com/mbosschaart/AI-Pulse/main/appcast.xml','SUPublicEDKey':'d454Z+1LhCUYsbGEi/Evx9DHT3kUntR1eOhdXc6BPAg=','SUEnableInstallerLauncherService':True,'SUEnableAutomaticChecks':False,'SUAutomaticallyUpdate':False,'SUAllowsAutomaticUpdates':False,'SUSendProfileInfo':False,'NSPrincipalClass':'NSApplication','CFBundleURLTypes':[{'CFBundleURLName':'AI Pulse','CFBundleURLSchemes':['aipulse']}],'NSHighResolutionCapable':True})
 else: info['NSExtension']={'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}
 (root/'Config'/f'{target}.plist').write_bytes(plistlib.dumps(info))
 ent={'com.apple.security.app-sandbox':True,'com.apple.security.application-groups':['$(DEVELOPMENT_TEAM).nl.martijn.aipulse']}
 if target=='app':
  ent['com.apple.security.network.client']=True
  ent['com.apple.security.temporary-exception.mach-lookup.global-name']=['$(PRODUCT_BUNDLE_IDENTIFIER)-spks','$(PRODUCT_BUNDLE_IDENTIFIER)-spki']
 (root/'Config'/f'{target}.entitlements').write_bytes(plistlib.dumps(ent))
scheme=proj/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
(scheme/'AIPulse.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{oid('appTarget')}" BuildableName="AI Pulse.app" BlueprintName="AIPulse" ReferencedContainer="container:AIPulse.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{oid('appTarget')}" BuildableName="AI Pulse.app" BlueprintName="AIPulse" ReferencedContainer="container:AIPulse.xcodeproj"/></BuildableProductRunnable></LaunchAction><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print(proj)
