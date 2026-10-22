#!/usr/bin/env python3
"""Generate GodsWord.xcodeproj/project.pbxproj with consistent UUIDs."""
import uuid, os

OUT = "/home/hatch/workspace/god-s-word/GodsWord.xcodeproj/project.pbxproj"

def uid(name):
    # Deterministic so regenerating the project keeps every ID (and the
    # scheme's BlueprintIdentifier) stable.
    return uuid.uuid5(uuid.NAMESPACE_URL, "godsword-pbxproj:" + name).hex[:24].upper()

# ---- collect ids ----
ids = {}
def I(name):
    if name not in ids:
        ids[name] = uid(name)
    return ids[name]

# File references
sources = [
    "GodsWord/GodsWordApp.swift",
    "GodsWord/Services/ModuleStore.swift",
    "GodsWord/Services/PersonalData.swift",
    "GodsWord/Services/GoogleDriveBackup.swift",
    "GodsWord/Services/ModuleLoader.swift",
    "GodsWord/Services/ReadingHistory.swift",
    "GodsWord/Services/Bookmark.swift",
    "GodsWord/Services/StrongsService.swift",
    "GodsWord/Services/iCloudSync.swift",
    "GodsWord/Services/PrivateBible.swift",
    "GodsWord/Services/BibleVersion.swift",
    "GodsWord/Services/BibleSource.swift",
    "GodsWord/Services/CommentaryService.swift",
    "GodsWord/Views/LibraryView.swift",
    "GodsWord/Views/BooksView.swift",
    "GodsWord/Views/ChaptersView.swift",
    "GodsWord/Views/ReaderView.swift",
    "GodsWord/Views/BookmarksView.swift",
    "GodsWord/Views/StrongsDefinitionView.swift",
    "GodsWord/Views/VerseNoteEditor.swift",
    "GodsWord/Views/ReadingSettingsView.swift",
    "GodsWord/Views/RepositoryView.swift",
    "GodsWord/Views/SourceEditView.swift",
    "GodsWord/Views/SourcesSettingsView.swift",
    "GodsWord/Views/SettingsView.swift",
    "GodsWord/Views/HistoryView.swift",
    "GodsWord/Views/EdgeNavigation.swift",
    "GodsWord/Views/CompareView.swift",
    "GodsWord/Views/LicenseNoticeView.swift",
    "GodsWord/Views/AssignBookmarkView.swift",
    "GodsWord/Views/AuxiliaryPanelView.swift",
]
resources = [
    "GodsWord/Assets.xcassets",
]
other_files = [
    "GodsWord/Info.plist",
    "GodsWord/GoogleOAuth.plist.template",
]

for f in sources + resources + other_files:
    I("fileref:" + f)
# groups
for g in ["main", "GodsWord", "Services", "Views", "Products"]:
    I("group:" + g)
# build phases & target & project
for n in ["buildfile:" + s for s in sources] + ["buildfile:" + r for r in resources]:
    I(n)
for n in ["PBXProject", "PBXNativeTarget", "SourcesPhase", "ResourcesPhase", "FrameworksPhase",
          "TargetConfigList", "ProjectConfigList", "TargetDebug", "TargetRelease",
          "ProjectDebug", "ProjectRelease", "SwiftPackageRef", "SwiftPackageDep",
          "SwiftPackageBuildFile"]:
    I(n)

def fileref(path, ftype, name=None):
    nm = name or os.path.basename(path)
    return (f'\t\t{I("fileref:" + path)} /* {nm} */ = {{isa = PBXFileReference; '
            f'lastKnownFileType = {ftype}; path = "{nm}"; sourceTree = "<group>"; }};')

L = []
A = L.append

A('// !$*UTF8*$!')
A('{')
A('\tarchiveVersion = 1;')
A('\tclasses = {')
A('\t};')
A('\tobjectVersion = 77;')
A('\tobjects = {')

# PBXBuildFile
A('')
A('/* Begin PBXBuildFile section */')
for s in sources:
    A(f'\t\t{I("buildfile:" + s)} /* {os.path.basename(s)} in Sources */ = {{isa = PBXBuildFile; fileRef = {I("fileref:" + s)} /* {os.path.basename(s)} */; }};')
for r in resources:
    A(f'\t\t{I("buildfile:" + r)} /* {os.path.basename(r)} in Resources */ = {{isa = PBXBuildFile; fileRef = {I("fileref:" + r)} /* {os.path.basename(r)} */; }};')
A(f'\t\t{I("SwiftPackageBuildFile")} /* SwordReader in Frameworks */ = {{isa = PBXBuildFile; productRef = {I("SwiftPackageDep")} /* SwordReader */; }};')
A('/* End PBXBuildFile section */')

# XCSwiftPackageProductDependency (its own section; must NOT go in a build phase's files)
A('')
A('/* Begin XCSwiftPackageProductDependency section */')
A(f'\t\t{I("SwiftPackageDep")} /* SwordReader */ = {{isa = XCSwiftPackageProductDependency; package = {I("SwiftPackageRef")} /* SwordReader */; productName = SwordReader; }};')
A('/* End XCSwiftPackageProductDependency section */')

# PBXFileReference
A('')
A('/* Begin PBXFileReference section */')
for s in sources:
    A(fileref(s, "sourcecode.swift"))
A(fileref("GodsWord/Assets.xcassets", "folder.assetcatalog", "Assets.xcassets"))
A(fileref("GodsWord/Info.plist", "text.plist.xml", "Info.plist"))
A(fileref("GodsWord/GoogleOAuth.plist.template", "text.plist.xml", "GoogleOAuth.plist.template"))
A(f'\t\t{I("fileref:app")} /* God\'s Word.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "God\'s Word.app"; sourceTree = BUILT_PRODUCTS_DIR; }};')
A('/* End PBXFileReference section */')

# PBXFrameworksBuildPhase
A('')
A('/* Begin PBXFrameworksBuildPhase section */')
A(f'\t\t{I("FrameworksPhase")} /* Frameworks */ = {{')
A('\t\t\tisa = PBXFrameworksBuildPhase;')
A('\t\t\tbuildActionMask = 2147483647;')
A('\t\t\tfiles = (')
A(f'\t\t\t\t{I("SwiftPackageBuildFile")} /* SwordReader in Frameworks */,')
A('\t\t\t);')
A('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
A('\t\t};')
A('/* End PBXFrameworksBuildPhase section */')

# PBXGroup
A('')
A('/* Begin PBXGroup section */')
A(f'\t\t{I("group:main")} /* main */ = {{')
A('\t\t\tisa = PBXGroup;')
A('\t\t\tchildren = (')
A(f'\t\t\t\t{I("group:GodsWord")} /* GodsWord */,')
A(f'\t\t\t\t{I("group:Products")} /* Products */,')
A('\t\t\t);')
A('\t\t\tsourceTree = "<group>";')
A('\t\t};')
A(f'\t\t{I("group:GodsWord")} /* GodsWord */ = {{')
A('\t\t\tisa = PBXGroup;')
A('\t\t\tchildren = (')
A(f'\t\t\t\t{I("fileref:GodsWord/GodsWordApp.swift")} /* GodsWordApp.swift */,')
A(f'\t\t\t\t{I("group:Services")} /* Services */,')
A(f'\t\t\t\t{I("group:Views")} /* Views */,')
A(f'\t\t\t\t{I("fileref:GodsWord/Assets.xcassets")} /* Assets.xcassets */,')
A(f'\t\t\t\t{I("fileref:GodsWord/Info.plist")} /* Info.plist */,')
A(f'\t\t\t\t{I("fileref:GodsWord/GoogleOAuth.plist.template")} /* GoogleOAuth.plist.template */,')
A('\t\t\t);')
A('\t\t\tpath = GodsWord;')
A('\t\t\tsourceTree = "<group>";')
A('\t\t};')
A(f'\t\t{I("group:Services")} /* Services */ = {{')
A('\t\t\tisa = PBXGroup;')
A('\t\t\tchildren = (')
for s in sources:
    if "/Services/" in s:
        A(f'\t\t\t\t{I("fileref:" + s)} /* {os.path.basename(s)} */,')
A('\t\t\t);')
A('\t\t\tpath = Services;')
A('\t\t\tsourceTree = "<group>";')
A('\t\t};')
A(f'\t\t{I("group:Views")} /* Views */ = {{')
A('\t\t\tisa = PBXGroup;')
A('\t\t\tchildren = (')
for s in sources:
    if "/Views/" in s:
        A(f'\t\t\t\t{I("fileref:" + s)} /* {os.path.basename(s)} */,')
A('\t\t\t);')
A('\t\t\tpath = Views;')
A('\t\t\tsourceTree = "<group>";')
A('\t\t};')
A(f'\t\t{I("group:Products")} /* Products */ = {{')
A('\t\t\tisa = PBXGroup;')
A('\t\t\tchildren = (')
A(f'\t\t\t\t{I("fileref:app")} /* God\'s Word.app */,')
A('\t\t\t);')
A('\t\t\tname = Products;')
A('\t\t\tsourceTree = "<group>";')
A('\t\t};')
A('/* End PBXGroup section */')

# PBXNativeTarget
A('')
A('/* Begin PBXNativeTarget section */')
A(f'\t\t{I("PBXNativeTarget")} /* God\'s Word */ = {{')
A('\t\t\tisa = PBXNativeTarget;')
A(f'\t\t\tbuildConfigurationList = {I("TargetConfigList")} /* Build configuration list for PBXNativeTarget "God\'s Word" */;')
A('\t\t\tbuildPhases = (')
A(f'\t\t\t\t{I("SourcesPhase")} /* Sources */,')
A(f'\t\t\t\t{I("FrameworksPhase")} /* Frameworks */,')
A(f'\t\t\t\t{I("ResourcesPhase")} /* Resources */,')
A('\t\t\t);')
A('\t\t\tbuildRules = (')
A('\t\t\t);')
A('\t\t\tdependencies = (')
A('\t\t\t);')
A('\t\t\tname = "God\'s Word";')
A('\t\t\tpackageProductDependencies = (')
A(f'\t\t\t\t{I("SwiftPackageDep")} /* SwordReader */,')
A('\t\t\t);')
A('\t\t\tproductName = "God\'s Word";')
A(f'\t\t\tproductReference = {I("fileref:app")} /* God\'s Word.app */;')
A('\t\t\tproductType = "com.apple.product-type.application";')
A('\t\t};')
A('/* End PBXNativeTarget section */')

# PBXProject
A('')
A('/* Begin PBXProject section */')
A(f'\t\t{I("PBXProject")} /* Project object */ = {{')
A('\t\t\tisa = PBXProject;')
A('\t\t\tattributes = {')
A('\t\t\t\tBuildIndependentTargetsInParallel = 1;')
A('\t\t\t\tLastUpgradeCheck = 1700;')
A('\t\t\t};')
A(f'\t\t\tbuildConfigurationList = {I("ProjectConfigList")} /* Build configuration list for PBXProject "GodsWord" */;')
A('\t\t\tcompatibilityVersion = "Xcode 16.0";')
A('\t\t\tdevelopmentRegion = en;')
A('\t\t\thasScannedForEncodings = 0;')
A('\t\t\tknownRegions = (')
A('\t\t\t\ten,')
A('\t\t\t);')
A('\t\t\tmainGroup = %s;' % I("group:main"))
A('\t\t\tpackageReferences = (')
A(f'\t\t\t\t{I("SwiftPackageRef")} /* SwordReader */,')
A('\t\t\t);')
A('\t\t\tproductRefGroup = %s /* Products */;' % I("group:Products"))
A('\t\t\tprojectDirPath = "";')
A('\t\t\tprojectRoot = "";')
A('\t\t\ttargets = (')
A(f'\t\t\t\t{I("PBXNativeTarget")} /* God\'s Word */,')
A('\t\t\t);')
A('\t\t};')
A('/* End PBXProject section */')

# PBXResourcesBuildPhase / PBXSourcesBuildPhase
A('')
A('/* Begin PBXResourcesBuildPhase section */')
A(f'\t\t{I("ResourcesPhase")} /* Resources */ = {{')
A('\t\t\tisa = PBXResourcesBuildPhase;')
A('\t\t\tbuildActionMask = 2147483647;')
A('\t\t\tfiles = (')
for r in resources:
    A(f'\t\t\t\t{I("buildfile:" + r)} /* {os.path.basename(r)} in Resources */,')
A('\t\t\t);')
A('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
A('\t\t};')
A('/* End PBXResourcesBuildPhase section */')
A('')
A('/* Begin PBXSourcesBuildPhase section */')
A(f'\t\t{I("SourcesPhase")} /* Sources */ = {{')
A('\t\t\tisa = PBXSourcesBuildPhase;')
A('\t\t\tbuildActionMask = 2147483647;')
A('\t\t\tfiles = (')
for s in sources:
    A(f'\t\t\t\t{I("buildfile:" + s)} /* {os.path.basename(s)} in Sources */,')
A('\t\t\t);')
A('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
A('\t\t};')
A('/* End PBXSourcesBuildPhase section */')

# XCBuildConfiguration
def config(name, settings):
    A(f'\t\t{I(name)} /* {name.split("Target")[0] if "Target" in name else name} */ = {{')
    A('\t\t\tisa = XCBuildConfiguration;')
    A('\t\t\tbuildSettings = {')
    for k, v in settings.items():
        A(f'\t\t\t\t{k} = {v};')
    A('\t\t\t};')
    A(f'\t\t\tname = {"Debug" if "Debug" in name else "Release"};')
    A('\t\t};')

A('')
A('/* Begin XCBuildConfiguration section */')
common_target = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "CODE_SIGN_STYLE": "Automatic",
    "DEVELOPMENT_TEAM": '""',
    "INFOPLIST_FILE": "GodsWord/Info.plist",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "MARKETING_VERSION": "1.0",
    "CURRENT_PROJECT_VERSION": "1",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.yuericlin.godsword",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "6.0",
    "TARGETED_DEVICE_FAMILY": "1",
}
config("TargetDebug", {**common_target})
config("TargetRelease", {**common_target})
config("ProjectDebug", {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu11",
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SDKROOT": "iphoneos",
})
config("ProjectRelease", {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "ENABLE_NS_ASSERTIONS": "NO",
    "GCC_C_LANGUAGE_STANDARD": "gnu11",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SDKROOT": "iphoneos",
    "VALIDATE_PRODUCT": "YES",
})
A('/* End XCBuildConfiguration section */')

# XCConfigurationList
A('')
A('/* Begin XCConfigurationList section */')
for listname, cfgs in [("TargetConfigList", ["TargetDebug", "TargetRelease"]),
                       ("ProjectConfigList", ["ProjectDebug", "ProjectRelease"])]:
    A(f'\t\t{I(listname)} /* Build configuration list for PBX{"NativeTarget" if "Target" in listname else "Project"} */ = {{')
    A('\t\t\tisa = XCConfigurationList;')
    A('\t\t\tbuildConfigurations = (')
    for c in cfgs:
        A(f'\t\t\t\t{I(c)} /* {"Debug" if "Debug" in c else "Release"} */,')
    A('\t\t\t);')
    A('\t\t\tdefaultConfigurationIsVisible = 0;')
    A(f'\t\t\tdefaultConfigurationName = {"Release" if "Project" in listname else "Release"};')
    A('\t\t};')
A('/* End XCConfigurationList section */')

# Swift package ref
A('')
A('/* Begin XCLocalSwiftPackageReference section */')
A(f'\t\t{I("SwiftPackageRef")} /* SwordReader */ = {{')
A('\t\t\tisa = XCLocalSwiftPackageReference;')
# relativePath is relative to the project directory (the folder containing
# .xcodeproj), so the package at the repo root is "SwordReader".
A('\t\t\trelativePath = SwordReader;')
A('\t\t};')
A('/* End XCLocalSwiftPackageReference section */')
A('')
A('/* Begin XCSwiftPackageProductDependency section */')
A(f'\t\t{I("SwiftPackageDep")} /* SwordReader */ = {{')
A('\t\t\tisa = XCSwiftPackageProductDependency;')
A(f'\t\t\tpackage = {I("SwiftPackageRef")} /* SwordReader */;')
A('\t\t\tproductName = SwordReader;')
A('\t\t};')
A('/* End XCSwiftPackageProductDependency section */')

A('\t};')
A(f'\trootObject = {I("PBXProject")} /* Project object */;')
A('}')

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as f:
    f.write("\n".join(L) + "\n")
print("wrote", OUT)

# sanity: every referenced id is defined
import re
text = open(OUT).read()
defined = set(re.findall(r"^\t\t([0-9A-F]{24}) /\*", text, re.M))
used = set(re.findall(r"= ([0-9A-F]{24})(?: /\*|;)", text))
used |= set(re.findall(r"\( ([0-9A-F]{24}) /\*", text))
missing = used - defined
print("defined:", len(defined), "missing refs:", len(missing), missing if missing else "")

# keep the shared scheme pointing at the (deterministic) target id
scheme_path = "/home/hatch/workspace/god-s-word/GodsWord.xcodeproj/xcshareddata/xcschemes/GodsWord.xcscheme"
scheme = open(scheme_path).read()
new_target = I("PBXNativeTarget")
scheme2 = re.sub(r'BlueprintIdentifier\s*=\s*"[0-9A-F]{24}"', f'BlueprintIdentifier = "{new_target}"', scheme)
open(scheme_path, "w").write(scheme2)
print("scheme BlueprintIdentifier ->", new_target)
