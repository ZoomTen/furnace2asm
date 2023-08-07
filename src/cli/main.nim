from parseopt import nil
from os import nil
import std/strutils
import ../convert
import ../versionInfo

proc showHelp() =
    echo """
fur2asm-cli [options] INPUT_FILE > OUTPUT_FILE

    -h, --help      Show this help screen.
    -o, --old       Convert to the legacy macros format.
    -v, --version   Show app version
    """

proc showAppVersionAndQuit() =
    quit "fur2asm-cli v$#.$#.$#" % [
        $VersionMajor, $VersionMinor, $VersionBuild
    ], QuitSuccess

proc showHelpAndQuit() {.inline.} =
    showHelp()
    quit(QuitSuccess)

when isMainModule:
    var
        args = parseopt.initOptParser(
            os.commandLineParams()
        )
        useOldMacros = false
    
    if parseopt.remainingArgs(args).len == 0:
        showHelpAndQuit()
    
    var
        inFile = ""
    
    while true:
        parseopt.next(args)
        case args.kind
        of parseopt.cmdEnd: break
        of parseopt.cmdArgument:
            if inFile == "":
                inFile = args.key.strip()
        of parseopt.cmdShortOption:
            case args.key.toLower()
            of "h":
                showHelpAndQuit()
            of "o":
                useOldMacros = true
            of "v":
                showAppVersionAndQuit()
            else:
                showHelp()
                quit(
                    "I don't understand the \"" & args.key & "\" option...",
                    QuitFailure
                )
        of parseopt.cmdLongOption:
            case args.key.toLower()
            of "help":
                showHelpAndQuit()
            of "old":
                useOldMacros = true
            of "version":
                showAppVersionAndQuit()
            else:
                showHelp()
                quit(
                    "I don't understand the \"" & args.key & "\" option...",
                    QuitFailure
                )
    
    if inFile == "":
        showHelpAndQuit()
    
    echo convertFile(
        inFile, useOldMacros
    )
