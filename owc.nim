import os
import parseopt, strformat, strutils
import std/[sets, marshal, streams, times, tables]

const helpText = """Usage: owc [options] [file]

Options:

  -m, --mark          : Mark wordcount progress
  --help              : Output this help message
  --version           : Output software version
"""


const
  versionText = "0.0.2"
  markFile = "owcmark.txt"
  separators = Whitespace + {',', '.', '?', '"', ';', '!', '(', ')', '*', '[',
      ']', '|', '>', '-'}
  nonTextProperties = toHashSet(@["visible-if:", "priority:", "frequency:",
      "min-choices:", "max-choices:", "max-visits:", "goto:", "game-over:"])
  textProperties = toHashSet(@["title:", "subtitle:"])
  locationToken: string = "###"
  storyletToken: string = "==="
  textLineStarter = Letters + {',', '.', '?', '!', ';', '(', ')', '"', '&'}


type
  Mode = enum
    help,
    version,
    error,
    run
  Operation = enum
    opCompare,
    opMark,
    opShow
  Location = ref object
    storylets, words: int
    id: string
  Report = ref object
    marked: DateTime
    locations: Table[string, Location]


func countWords(s: string): int =
  var count: int = 0
  for word in s.split(separators):
    if word.isEmptyOrWhitespace:
      continue
    else:
      inc count
  count


func applyLine(location: Location, line: string): Location =
  var z = 0
  if line[0] == '*':
    z = countWords(line[1..^1].split('>', maxsplit = 1)[0])
  elif line.startsWith(storyletToken):
    inc location.storylets
  elif textLineStarter.contains(line[0]):
    let prefix = line[0..line.find(':')]
    if nonTextProperties.contains(prefix):
      z = 0
    elif textProperties.contains(prefix):
      z = countWords(line.split(':', maxsplit = 1)[1])
    else:
      z = countWords(line)
  else:
    z = 0
  if z > 0:
    location.words += z
  location


proc main(filename: string, operation: Operation) =
  var locations: seq[Location] = @[]

  for line in filename.lines:
    if line.startsWith(locationToken):
      locations.add(
        Location(
          id: line[3..^1].strip(),
          words: 0,
          storylets: 0,
        )
      )
      continue
    elif locations.len == 0:
      continue
    elif line.isEmptyOrWhitespace:
      continue
    else:
      discard locations[^1].applyLine(line)

  case operation
  of opShow:
    var
      totalWords = 0
      totalStorylets = 0
    for l in locations:
      echo fmt"{l.id}"
      echo fmt"  words: {l.words}"
      echo fmt"  storylets: {l.storylets}"
      totalWords += l.words
      totalStorylets += l.storylets
    echo &"\ntotal words: {totalWords}"
    echo fmt"total storylets: {totalStorylets}"

  of opCompare:
    var strm = newFileStream(markFile, fmRead)
    if strm.isNil:
      echo fmt"Could not load bookmark file {markFile}.  Run with --mark to create one."
      return

    var r: Report
    try:
      load(strm, r)
    except IOError:
      echo fmt"De-serializing markfile failed"
      return

    echo r.marked.format("yyyy-MM-dd HH:mm:ss")
    let q = initDuration(seconds = (now() - r.marked).inSeconds)
    echo fmt"{q} ago"
    echo "----"
    var
      totalWords = 0
      totalStorylets = 0
    var old: Location
    for l in locations:
      echo fmt"{l.id}:"
      if r.locations.pop(l.id, old):
        totalWords += l.words - old.words
        totalStorylets += l.storylets - old.storylets
        if old.words != l.words:
          echo fmt"  words:     {old.words} --> {l.words} ({l.words - old.words:+})"
        else:
          echo fmt"  words:     {old.words}"
        if old.storylets < l.storylets:
          echo fmt"  storylets: {old.storylets} --> {l.storylets} ({l.storylets - old.storylets:+})"
        else:
          echo fmt"  storylets: {old.storylets}"
      else:
        totalWords += l.words
        totalStorylets += l.storylets
        echo fmt"  words:     0 --> {l.words} ({l.words:+})"
        echo fmt"  storylets: 0 --> {l.storylets} ({l.storylets:+})"
    # Locations that are in the old mark but not in the current file
    for l in r.locations.values:
      echo fmt"{l.id}:"
      totalWords -= l.words
      totalStorylets -= l.storylets
      echo fmt"  words:     {l.words} --> 0 (-{l.words})"
      echo fmt"  storylets: {l.storylets} --> 0 (-{l.storylets})"


    echo &"\ntotal:\n  words: {totalWords:>+10}\n  storylets: {totalStorylets:>+6}"
  of opMark:
    var strm = newFileStream(markFile, fmWrite)

    # let locTable = foldl(locations, a[b.id] = b, initTable[string, Location]())
    var locTable = initTable[string, Location]()
    for l in locations:
      locTable[l.id] = l
    let report = Report(marked: now(), locations: locTable)
    store(strm, report)
    echo "Word count marked"
    strm.close()


when isMainModule:
  var p = initOptParser(shortNoVal = {'h', 'm'}, longNoVal = @["help", "mark", "version"])
  var filename: string
  var operation = if fileExists(markFile): opCompare else: opShow
  var mode = run

  for kind, key, val in p.getOpt():
    case kind
    of cmdArgument:
      filename = key
    else:
      case key:
        of "m", "mark":
          operation = opMark
        of "help":
          mode = help
        of "version":
          mode = version
        else:
          echo fmt"I don't understand option {key}!"
          mode = error
  case mode
  of error, help:
    echo helpText
  of version:
    echo versionText
  of run:
    if filename == "":
      echo "No filename given"
    elif not fileExists(filename):
      echo fmt"File {filename} not found!"
    else:
      main(filename, operation)
