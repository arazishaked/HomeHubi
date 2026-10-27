import hashlib, os, sys
root = sys.argv[1]
src = os.path.join(root, "HomeHub")
swift = sorted(f for f in os.listdir(src) if f.endswith(".swift"))

def uid(name):
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()

P = {k: uid(k) for k in ["project", "main", "group", "products", "app", "target", "sources", "frameworks",
                         "resources", "plist", "pcl", "tcl", "pdebug", "prelease", "tdebug", "trelease"]}
fref = {f: uid("fref:" + f) for f in swift}
bfile = {f: uid("bfile:" + f) for f in swift}

L = []
w = L.append
w("// !$*UTF8*$!")
w("{")
w("\tarchiveVersion = 1;")
w("\tclasses = {")
w("\t};")
w("\tobjectVersion = 56;")
w("\tobjects = {")
w("")
w("/* Begin PBXBuildFile section */")
for f in swift:
    w(f"\t\t{bfile[f]} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref[f]} /* {f} */; }};")
w("/* End PBXBuildFile section */")
w("")
w("/* Begin PBXFileReference section */")
w(f"\t\t{P['app']} /* HomeHub.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = HomeHub.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
w(f"\t\t{P['plist']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
for f in swift:
    w(f"\t\t{fref[f]} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f}; sourceTree = \"<group>\"; }};")
w("/* End PBXFileReference section */")
w("")
w("/* Begin PBXFrameworksBuildPhase section */")
w(f"\t\t{P['frameworks']} /* Frameworks */ = {{")
w("\t\t\tisa = PBXFrameworksBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXFrameworksBuildPhase section */")
w("")
w("/* Begin PBXGroup section */")
w(f"\t\t{P['main']} = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
w(f"\t\t\t\t{P['group']} /* HomeHub */,")
w(f"\t\t\t\t{P['products']} /* Products */,")
w("\t\t\t);")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w(f"\t\t{P['group']} /* HomeHub */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
for f in swift:
    w(f"\t\t\t\t{fref[f]} /* {f} */,")
w(f"\t\t\t\t{P['plist']} /* Info.plist */,")
w("\t\t\t);")
w("\t\t\tpath = HomeHub;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w(f"\t\t{P['products']} /* Products */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
w(f"\t\t\t\t{P['app']} /* HomeHub.app */,")
w("\t\t\t);")
w("\t\t\tname = Products;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w("/* End PBXGroup section */")
w("")
w("/* Begin PBXNativeTarget section */")
w(f"\t\t{P['target']} /* HomeHub */ = {{")
w("\t\t\tisa = PBXNativeTarget;")
w(f"\t\t\tbuildConfigurationList = {P['tcl']} /* Build configuration list for PBXNativeTarget \"HomeHub\" */;")
w("\t\t\tbuildPhases = (")
w(f"\t\t\t\t{P['sources']} /* Sources */,")
w(f"\t\t\t\t{P['frameworks']} /* Frameworks */,")
w(f"\t\t\t\t{P['resources']} /* Resources */,")
w("\t\t\t);")
w("\t\t\tbuildRules = (")
w("\t\t\t);")
w("\t\t\tdependencies = (")
w("\t\t\t);")
w("\t\t\tname = HomeHub;")
w("\t\t\tproductName = HomeHub;")
w(f"\t\t\tproductReference = {P['app']} /* HomeHub.app */;")
w("\t\t\tproductType = \"com.apple.product-type.application\";")
w("\t\t};")
w("/* End PBXNativeTarget section */")
w("")
w("/* Begin PBXProject section */")
w(f"\t\t{P['project']} /* Project object */ = {{")
w("\t\t\tisa = PBXProject;")
w("\t\t\tattributes = {")
w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
w("\t\t\t\tLastSwiftUpdateCheck = 1500;")
w("\t\t\t\tLastUpgradeCheck = 1500;")
w("\t\t\t\tTargetAttributes = {")
w(f"\t\t\t\t\t{P['target']} = {{")
w("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
w("\t\t\t\t\t};")
w("\t\t\t\t};")
w("\t\t\t};")
w(f"\t\t\tbuildConfigurationList = {P['pcl']} /* Build configuration list for PBXProject \"HomeHub\" */;")
w("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
w("\t\t\tdevelopmentRegion = he;")
w("\t\t\thasScannedForEncodings = 0;")
w("\t\t\tknownRegions = (")
w("\t\t\t\ten,")
w("\t\t\t\the,")
w("\t\t\t\tBase,")
w("\t\t\t);")
w(f"\t\t\tmainGroup = {P['main']};")
w(f"\t\t\tproductRefGroup = {P['products']} /* Products */;")
w("\t\t\tprojectDirPath = \"\";")
w("\t\t\tprojectRoot = \"\";")
w("\t\t\ttargets = (")
w(f"\t\t\t\t{P['target']} /* HomeHub */,")
w("\t\t\t);")
w("\t\t};")
w("/* End PBXProject section */")
w("")
w("/* Begin PBXResourcesBuildPhase section */")
w(f"\t\t{P['resources']} /* Resources */ = {{")
w("\t\t\tisa = PBXResourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXResourcesBuildPhase section */")
w("")
w("/* Begin PBXSourcesBuildPhase section */")
w(f"\t\t{P['sources']} /* Sources */ = {{")
w("\t\t\tisa = PBXSourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
for f in swift:
    w(f"\t\t\t\t{bfile[f]} /* {f} in Sources */,")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXSourcesBuildPhase section */")
w("")

common = [
 'ALWAYS_SEARCH_USER_PATHS = NO;', 'CLANG_ENABLE_MODULES = YES;', 'CLANG_ENABLE_OBJC_ARC = YES;',
 'COPY_PHASE_STRIP = NO;', 'ENABLE_STRICT_OBJC_MSGSEND = YES;', 'GCC_C_LANGUAGE_STANDARD = gnu11;',
 'IPHONEOS_DEPLOYMENT_TARGET = 16.0;', 'SDKROOT = iphoneos;',
]
debug = ['DEBUG_INFORMATION_FORMAT = dwarf;', 'ENABLE_TESTABILITY = YES;', 'GCC_OPTIMIZATION_LEVEL = 0;',
         'ONLY_ACTIVE_ARCH = YES;', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;', 'SWIFT_OPTIMIZATION_LEVEL = "-Onone";']
release = ['DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";', 'ENABLE_NS_ASSERTIONS = NO;', 'SWIFT_COMPILATION_MODE = wholemodule;',
           'SWIFT_OPTIMIZATION_LEVEL = "-O";', 'VALIDATE_PRODUCT = YES;']
target = [
 'CODE_SIGN_STYLE = Automatic;', 'CURRENT_PROJECT_VERSION = 1;', 'DEVELOPMENT_TEAM = "";', 'ENABLE_PREVIEWS = YES;',
 'GENERATE_INFOPLIST_FILE = NO;', 'INFOPLIST_FILE = HomeHub/Info.plist;',
 'LD_RUNPATH_SEARCH_PATHS = (\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t);',
 'MARKETING_VERSION = 1.0;', 'PRODUCT_BUNDLE_IDENTIFIER = com.homehub.app;', 'PRODUCT_NAME = "$(TARGET_NAME)";',
 'SWIFT_EMIT_LOC_STRINGS = YES;', 'SWIFT_VERSION = 5.0;', 'TARGETED_DEVICE_FAMILY = "1,2";',
]
def cfg(key, name, settings):
    w(f"\t\t{P[key]} /* {name} */ = {{")
    w("\t\t\tisa = XCBuildConfiguration;")
    w("\t\t\tbuildSettings = {")
    for s in sorted(settings):
        w("\t\t\t\t" + s)
    w("\t\t\t};")
    w(f"\t\t\tname = {name};")
    w("\t\t};")
w("/* Begin XCBuildConfiguration section */")
cfg("pdebug", "Debug", common + debug)
cfg("prelease", "Release", common + release)
cfg("tdebug", "Debug", target)
cfg("trelease", "Release", target)
w("/* End XCBuildConfiguration section */")
w("")
w("/* Begin XCConfigurationList section */")
for key, label, d, r in [("pcl", 'PBXProject "HomeHub"', "pdebug", "prelease"), ("tcl", 'PBXNativeTarget "HomeHub"', "tdebug", "trelease")]:
    w(f"\t\t{P[key]} /* Build configuration list for {label} */ = {{")
    w("\t\t\tisa = XCConfigurationList;")
    w("\t\t\tbuildConfigurations = (")
    w(f"\t\t\t\t{P[d]} /* Debug */,")
    w(f"\t\t\t\t{P[r]} /* Release */,")
    w("\t\t\t);")
    w("\t\t\tdefaultConfigurationIsVisible = 0;")
    w("\t\t\tdefaultConfigurationName = Release;")
    w("\t\t};")
w("/* End XCConfigurationList section */")
w("\t};")
w(f"\trootObject = {P['project']} /* Project object */;")
w("}")

proj = os.path.join(root, "HomeHub.xcodeproj")
os.makedirs(os.path.join(proj, "project.xcworkspace"), exist_ok=True)
os.makedirs(os.path.join(proj, "xcshareddata", "xcschemes"), exist_ok=True)
open(os.path.join(proj, "project.pbxproj"), "w").write("\n".join(L) + "\n")
open(os.path.join(proj, "project.xcworkspace", "contents.xcworkspacedata"), "w").write(
'''<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
''')
ref = f'''<BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{P['target']}"
               BuildableName = "HomeHub.app"
               BlueprintName = "HomeHub"
               ReferencedContainer = "container:HomeHub.xcodeproj">
            </BuildableReference>'''
open(os.path.join(proj, "xcshareddata", "xcschemes", "HomeHub.xcscheme"), "w").write(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            {ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
''')
print("files:", len(swift), swift)
