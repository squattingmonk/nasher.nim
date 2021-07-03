import unittest
from sequtils import zip
from strutils import contains, `%`

import nasher/pkgparser

proc dumpTarget(target: Target) =
  ## Helps debug failing tests
  echo "Target: ", target.name
  for key, value in target.fieldPairs:
    echo "  ", key, ": ", value

template checkErrorMsg(msg: string, body: untyped) =
  ## Runs ``body`` and checks that any raised exception message contains
  ## ``msg``.
  try:
    body
  except:
    check msg in getCurrentExceptionMsg()
    raise

  

suite "Cfg file parsing":
  test "Error on malformed syntax":
    expect PackageError:
      discard parsePackageString("""
      [package
      name = "foo"
      """)

  test "Empty package file yields empty target list":
    check parsePackageString("").len == 0

  test "No targets defined yields empty target list":
    check:
      parsePackageString("""
      [package]
      name = "foo"
      file = "bar"
      """).len == 0

  test "Error if [package] section occurs after other sections":
    expect PackageError:
      checkErrorMsg "[package] section must be declared before other sections":
        discard parsePackageString("""
        [sources]
        [package]
        """)

  test "Error on duplicate [package] section":
    expect PackageError:
      checkErrorMsg "duplicate [package] section":
        discard parsePackageString("""
        [package]
        [package]
        """)

  test "No error if [package] section absent":
    let targets = parsePackageString("""
    [target]
    name = "foo"
    """)
    check: targets.len == 1
  
  test "[sources], [rules], and [aliases] can be top-level sections":
    check parsePackageString("""
    [sources]
    [rules]
    [aliases]

    [target]
    name = "foo"
    """).len == 1

  test "[sources], [rules], and [aliases] sections can belong to [package] or [target]":
    let targets = parsePackageString("""
    [package]

      [sources]
      include = "foo"

      [rules]
      foo = "foo"

      [aliases]
      foo = "src/foo"

    [target]
    name = "bar"

      [sources]
      include = "bar"

      [rules]
      bar = "bar"

      [aliases]
      bar = "src/bar"

    [target]
    name = "foo"
    """)
    
    check:
      targets.len == 2
      targets[0].includes == @["bar"]
      targets[0].rules == @[(pattern: "bar", dest: "bar")]
      targets[0].aliases.len == 2
      targets[0].aliases["foo"] == "src/foo"
      targets[0].aliases["bar"] == "src/bar"

      targets[1].includes == @["foo"]
      targets[1].rules == @[(pattern: "foo", dest: "foo")]
      targets[1].aliases.len == 1
      targets[1].aliases["foo"] == "src/foo"

  test "[package.{sources,rules,aliases}] must be declared inside [package] or at top-level":
    check parsePackageString("""
    [package]
      [package.sources]
      [package.rules]
      [package.aliases]
    """).len == 0

    check parsePackageString("""
    [package.sources]
    [package.rules]
    [package.aliases]
    """).len == 0

    for section in ["sources", "rules", "aliases"]:
      expect PackageError:
        checkErrorMsg "[package.$1] must be declared within [package]" % section:
          discard parsePackageString("""
          [target]
          name = "foo"
            [package.$1]
          """ % section)

  test "[target.{sources,rules,aliases}] must be declared inside [target]":
    check parsePackageString("""
    [target]
    name = "foo"
      [target.sources]
      [target.rules]
      [target.aliases]
    """).len == 1

    for section in ["sources", "rules", "aliases"]:
      expect PackageError:
        checkErrorMsg "[target.$1] must be declared within [target]" % section:
          discard parsePackageString("""
          [package]
          name = "foo"
          [target.$1]
          """ % section)

  test "Error on unknown key in [*.sources]":
    for context in ["package", "target"]:
      expect PackageError:
        checkErrorMsg "invalid key 'foo' for section [$1.sources]" % context:
          discard parsePackageString("""
          [$1]
          name = "foo"

            [$1.sources]
            foo = "bar"
          """ % context)

      expect PackageError:
        checkErrorMsg "invalid key 'foo' for section [$1.sources]" % context:
          discard parsePackageString("""
          [$1]
          name = "foo"

            [sources]
            foo = "bar"
          """ % context)

  test "One target per [target] section":
    let targets = parsePackageString("""
    [package]
    name = "foo"
    file = "bar.mod"

    [target]
    name = "one"

    [target]
    name = "two"
    """)
    check:
      targets.len == 2
      targets[0].name == "one"
      targets[1].name == "two"

  test "Error if target has no name":
    expect PackageError:
      checkErrorMsg "target 1 is unnamed":
        discard parsePackageString("""
        [target]
        file = "foo.mod"
        """)

    expect PackageError:
      checkErrorMsg "target 2 is unnamed":
        discard parsePackageString("""
        [target]
        name = "foo"

        [target]
        file = "bar.mod"
        """)

  test "{package,target}.{version,url,author} fields ignored":
    check:
      parsePackageString("""
      [package]
      version = "0.1.0"
      url = "www.example.com"
      author = "John Doe <johndoe@example.com>"

      [target]
      name = "foo"
      version = "0.1.0"
      url = "www.example.com"
      author = "John Doe <johndoe@example.com>"
      """).len == 1

  test "target.{name,description} not inherited from [package]":
    expect PackageError:
      checkErrorMsg "target 1 is unnamed":
        discard parsePackageString("""
        [package]
        name = "foo"

        [target]
        """)

    let target = parsePackageString("""
    [package]
    name = "foo"
    description = "bar"

    [target]
    name = "bar"
    """)[0]
    check:
      target.description == ""

  test "target.{file,branch,modName,modMinGameVersion} inherit from [package]":
    let targets = parsePackageString("""
    [package]
    file = "foo.mod"
    branch = "master"
    modName = "foobar"
    modMinGameVersion = "1.73"

    [target]
    name = "no-inherit"
    file = "bar.mod"
    branch = "baz"
    modName = "qux"
    modMinGameVersion = "1.69"

    [target]
    name = "inherit"
    """)
    check:
      targets.len == 2
      targets[0].file == "bar.mod"
      targets[0].branch == "baz"
      targets[0].modName == "qux"
      targets[0].modMinGameVersion == "1.69"

      targets[1].file == "foo.mod"
      targets[1].branch == "master"
      targets[1].modName == "foobar"
      targets[1].modMinGameVersion == "1.73"

  test "target.{includes,excludes,filters,flags} inherit from [package]":
    let targets = parsePackageString("""
    [package]
    include = "foo/*"
    exclude = "bar/*"
    filter = "*.ncs"
    flags = "--foo"

    [target]
    name = "bar"
    include = "bar/*"
    exclude = "foo/*"
    filter = "*.ndb"
    flags = "--bar"

    [target]
    name = "foo"
    """)
    check:
      targets.len == 2
      targets[0].name == "bar"
      targets[0].includes == @["bar/*"]
      targets[0].excludes == @["foo/*"]
      targets[0].filters == @["*.ndb"]
      targets[0].flags == @["--bar"]
      targets[1].name == "foo"
      targets[1].includes == @["foo/*"]
      targets[1].excludes == @["bar/*"]
      targets[1].filters == @["*.ncs"]
      targets[1].flags == @["--foo"]

  test "target.{includes,excludes,filters,flags} values added to seq when seen multiple times":
    let target = parsePackageString("""
    [target]
    name = "foo"
    include = "foo"
    include = "bar"
    exclude = "baz"
    exclude = "qux"
    filter = "*.foo"
    filter = "*.bar"
    flags = "--foo"
    flags = "--bar"
    """)[0]
    check:
      target.includes == @["foo", "bar"]
      target.excludes == @["baz", "qux"]
      target.filters == @["*.foo", "*.bar"]
      target.flags == @["--foo", "--bar"]
  
  test "Unpack rules added to seq":
    let target = parsePackageString("""
    [rules]
    foo = "foo/"
    bar = "bar/"

    [target]
    name = "foo"
    """)[0]
    check:
      target.rules == @[(pattern: "foo", dest: "foo/"), (pattern: "bar", dest: "bar/")]

  test "Unpack rules inherited from [package]":
    let targets = parsePackageString("""
    [rules]
    foo = "foo/"

    [target]
    name = "bar"
    bar = "bar/"

    [target]
    name = "foo"
    """)
    check:
      targets.len == 2
      targets[0].rules == @[(pattern: "bar", dest: "bar/")]
      targets[1].rules == @[(pattern: "foo", dest: "foo/")]

  test "Unknown keys in [target] treated as unpack rules":
    let target = parsePackageString("""
    [target]
    name = "foo"
    foo = "foo/"
    bar = "bar/"
    """)[0]
    check:
      target.rules == @[(pattern: "foo", dest: "foo/"), (pattern: "bar", dest: "bar/")]

  test "[target.aliases] merges [package.aliases]":
    let targets = parsePackageString("""
    [aliases]
    utils = "src/utils"
    core = "src/core"

    [target]
    name = "foo"
      
      [aliases]
      utils = "../sm-utils/src"

    [target]
    name = "bar"
    """)

    check:
      targets.len == 2
      targets[0].aliases.len == 2
      targets[0].aliases["utils"] == "../sm-utils/src"
      targets[0].aliases["core"] == "src/core"
      targets[1].aliases.len == 2
      targets[1].aliases["utils"] == "src/utils"
      targets[1].aliases["core"] == "src/core"

  test "Parse package string":
    let pkg = """
      [package]
      name = "Test Package"
      description = "The package description"

        [package.sources]
        include = "src/**/*.{nss,json}"

        [package.rules]
        "*" = "src"

        [package.aliases]
        sm-utils = "sm-utils/src"

      [target]
      name = "module"
      file = "core_framework.mod"
      description = "A demo module"

      [target]
      name = "erf"
      file = "core_framework.erf"
      description = "An importable erf"

        [target.sources]
        exclude = "src/test_*.nss"
        exclude = "src/_*.nss"
        filter = "*.ncs"

        [target.aliases]
        core = "src/core"
        sm-utils = "src/utils"
      """

    let
      targetA = Target(name: "module",
                       file: "core_framework.mod",
                       description: "A demo module",
                       includes: @["src/**/*.{nss,json}"],
                       rules: @[(pattern: "*", dest: "src")],
                       aliases: newStringTable({"sm-utils": "sm-utils/src"}))
      targetB = Target(name: "erf",
                       file: "core_framework.erf",
                       description: "An importable erf",
                       includes: @["src/**/*.{nss,json}"],
                       excludes: @["src/test_*.nss", "src/_*.nss"],
                       filters: @["*.ncs"],
                       rules: @[(pattern: "*", dest: "src")],
                       aliases: newStringTable({"sm-utils": "src/utils", "core": "src/core"}))
      manual = @[targetA, targetB]
      parsed = parsePackageString(pkg)
    
    check parsed.len == manual.len
    for (a, b) in zip(manual, parsed):
      check a == b
