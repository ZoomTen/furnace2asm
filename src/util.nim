import binstreams
import strutils

proc readCStr*(stream: var MemStream): string =
    ##[
        Read a zero-terminated string. Not UTF-8 sensitive!
    ]##
    var
        charToAdd = stream.read(char)
    result = ""
    while charToAdd != '\x00': # this is rather shitty
        result &= charToAdd
        charToAdd = stream.read(char)

proc toTitle*(str: string): string =
    ##[
        Converts a space separated word into Almost Title Case
    ]##
    result = ""
    for word in str.split(" "):
        result &= word[0].toUpperAscii()
        result &= word.substr(1)