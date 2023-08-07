# Package

version       = "0.1.0"
author        = "Zumi Daxuya"
description   = "A new awesome nimble package"
license       = "MIT"
skipDirs      = @["src"]

# Dependencies

requires [
  "nim >= 1.6.0",
  "binstreams#4715f6c",
  "zippy#a3fd6f0"
]

when defined(withGui):
  requires "wNim#4dc3afd"

# Configuration

import strformat, strutils

const
  projectDir = "src"
  mainGuiFile = fmt"{projectDir}/gui/main"
  mainCliFile = fmt"{projectDir}/cli/main"
  resDir     = fmt"{projectDir}/res"

const
  resCompiler = "i686-w64-mingw32-windres"
  resFlags    = ["-O coff", fmt"{resDir}/fur2asm.rc", fmt"-o {resDir}/fur2asm.res"]

const
  cFlags = [
    "-flto", "-O3", "-ffunction-sections", "-fdata-sections"
  ]
  ldFlags = [
    "-flto", "-O3", "-s", "-Wl,--gc-sections"
  ]

var
  outFile     = "fur2asm"
  outCliFile  = "fur2asm-cli"

# Tasks

when defined(mingw):
  when findExe(resCompiler) == "":
    {.error: "Can't find windres!".}

when defined(windows) or defined(mingw):
  outFile &= ".exe"
  outCliFile &= ".exe"

let
  mingwFlag = when defined(mingw):
      "-d:mingw"
    else: ""
  winxpFlag = when defined(mingw) or defined(windows):
      "--define:useWinXP --cpu:i386"
    else: ""
  mmFlag = when (NimMajor > 1):
      "--mm:arc"
    else: "--gc:arc"

# Maybe I should've used Nake...

task runExec, "Run generated exe":
  if defined(windows):
    exec outFile
  elif defined(linux):
    exec fmt"wine {outCliFile}"

task makeDeps, "Make dependencies":
  exec "nimble install -d"
  when defined(withGui):
    exec fmt"{resCompiler} {resFlags.join($' ')}"

task makeDevel, "Make development build":
  makeDepsTask()
  when defined(withGui):
    when not defined(windows) or not defined(mingw):
      {.fatal: "GUI build is Windows-only! If cross compiling from another system, pass -d:mingw!".}
    selfExec fmt"c {mmFlag} --app:gui {mingwFlag} {winxpFlag} -o:{outFile} {mainGuiFile}"
  when not defined(guiOnly):
    selfExec fmt"c {mmFlag} --app:console {mingwFlag} {winxpFlag} -o:{outCliFile} {mainCliFile}"

task testDevel, "Test development build":
  makeDevelTask()
  runExecTask()

task makeRelease, "Make release build":
  makeDepsTask()
  when defined(withGui):
    when not defined(windows) or not defined(mingw):
      {.fatal: "GUI build is Windows-only! If cross compiling from another system, pass -d:mingw!".}
    selfExec fmt"""c {mmFlag} --app:gui -d:danger {mingwFlag} {winxpFlag} --passC:"{cFlags.join($' ')}" --passL:"{ldFlags.join($' ')}" -o:{outFile} {mainGuiFile}"""
  when not defined(guiOnly):
    selfExec fmt"""c {mmFlag} --app:console -d:danger {mingwFlag} {winxpFlag} --passC:"{cFlags.join($' ')}" --passL:"{ldFlags.join($' ')}" -o:{outCliFile} {mainCliFile}"""

task testRelease, "Test release build":
  makeReleaseTask()
  runExecTask()

task clean, "Clean up artifacts":
  for base in [outFile,outCliFile]:
    for exe in [base, base & ".exe"]:
      rmFile exe
  rmFile fmt"{resDir}/fur2asm.res"
