import parsecfg, strformat, streams, strtabs, strutils

export strtabs

type
  PackageError* = object of CatchableError

  Target* = object
    name*, description*, file*, branch*, modName*, modMinGameVersion*: string
    includes*, excludes*, filters*, flags*: seq[string]
    rules*: seq[Rule]
    aliases*: StringTableRef

  Rule* = tuple[pattern, dest: string]

proc raisePackageError(msg: string) =
  ## Raises a ``PackageError`` containing message ``msg``.
  raise newException(PackageError, msg)

proc raisePackageError(p: CfgParser, msg: string) =
  ## Raises a ``PackageError`` containing message ``msg`` using info from ``p``
  ## to show the location of the error.
  raise newException(PackageError, "Error parsing $1($2:$3): $4" %
    [p.getFilename, $p.getLine, $p.getColumn, msg])

proc `==`*(a, b: Target): bool =
  result = true
  for key, valA, valB in fieldPairs(a, b):
    when valA is StringTableRef:
      if $valA != $valB:
        return false
    else:
      if valA != valB:
        return false

proc initTarget: Target =
  result.aliases = newStringTable()

proc validTargetChars(name: string): bool =
  name.allCharsInSet({'a'..'z', '0'..'9', '_', '-'})

proc addTarget(targets: var seq[Target], target: var Target, defaults: Target) =
  ## Adds ``target`` to  ``targets``. Missing fields other than `name` and
  ## `description` are copied from ``defaults``.
  if target.name.len == 0:
    raisePackageError(fmt"target {targets.len + 1} is unnamed")

  # Merge unset aliases from ``defaults``
  for key, val in defaults.aliases.pairs:
    if key notin target.aliases:
      target.aliases[key] = val

  for key, targetVal, defaultVal in fieldPairs(target, defaults):
    case key
    of "name", "description":
      ## These values are not inherited from the [package] section
      discard
    of "aliases":
      discard
    else:
      if targetVal.len == 0:
        targetVal = defaultVal
  targets.add(target)

proc parsePackageStream*(s: Stream, filename: string): seq[Target] =
  var
    p: CfgParser
    context, section, key: string
    defaults = initTarget()
    target = initTarget()

  open(p, s, filename)
  while true:
    var e = p.next
    case e.kind
    of cfgEof:
      if context == "target":
        result.addTarget(target, defaults)
      break
    of cfgSectionStart:
      # echo fmt"Section: [{e.section}]"
      case e.section.toLower
      of "package":
        if section == "package":
          p.raisePackageError("duplicate [package] section")
        elif section.len > 0:
          p.raisePackageError("[package] section must be declared before other sections")
        context = "package"
      of "target":
        case context
        of "package", "":
          defaults = target
        of "target":
          result.addTarget(target, defaults)
        else: assert(false)
        target = initTarget()
        context = "target"
      of "sources", "rules", "aliases":
        discard
      of "package.sources", "package.rules", "package.aliases":
        if context in ["target"]:
          p.raisePackageError(fmt"[{e.section}] must be declared within [package]")
      of "target.sources", "target.rules", "target.aliases":
        if context in ["package", ""]:
          p.raisePackageError(fmt"[{e.section}] must be declared within [target]")
      else:
        p.raisePackageError(fmt"invalid section [{e.section}]")

      # Trim context from subsection
      section = e.section.toLower.rsplit('.', maxsplit = 1)[^1]
    of cfgKeyValuePair, cfgOption:
      # echo fmt"Option: {e.key} = {e.value}"
      case section
      of "package", "target":
        case e.key
        of "name":
          if section == "target":
            let name = e.value.toLower
            if name == "all" or not name.validTargetChars:
              p.raisePackageError(fmt"invalid target name '{name}'")
            else:
              target.name = name
        of "description":
          if section == "target":
            target.description = e.value
        of "file": target.file = e.value
        of "flags": target.flags.add(e.value)
        of "modName": target.modName = e.value
        of "modMinGameVersion": target.modMinGameVersion = e.value
        of "branch": target.branch = e.value
        # Keep for backwards compatibility, but prefer [{package,target}.sources]
        of "source", "include": target.includes.add(e.value)
        of "exclude": target.excludes.add(e.value)
        of "filter": target.filters.add(e.value)
        # Unused, but kept for backwards compatibility
        of "version", "url", "author": discard
        else:
          # Treat any unknown keys as unpack rules. Unfortunately, this prevents
          # us from detecting incorrect keys, so nasher may work unexpectedly.
          # In the future, we will issue a warning here.
          target.rules.add((e.key, e.value))
      of "sources":
        case e.key
        of "include": target.includes.add(e.value)
        of "exclude": target.excludes.add(e.value)
        of "filter": target.filters.add(e.value)
        else:
          p.raisePackageError(fmt"invalid key '{e.key}' for section [{context}.{section}]")
      of "rules":
        target.rules.add((e.key, e.value))
      of "aliases":
        target.aliases[e.key] = e.value
      else:
        discard
    of cfgError:
      p.raisePackageError(e.msg)
  close(p)

proc parsePackageString*(s: string, filename = "[stream]"): seq[Target] =
  let stream = newStringStream(s)
  parsePackageStream(stream, filename)

proc parseCfgPackageFile(filename: string): seq[Target] =
  let fileStream = newFileStream(filename)
  if fileStream.isNil:
    raise newException(IOError, fmt"Could not lead package file {filename}")
  parsePackageStream(fileStream, filename)
