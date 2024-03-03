import ./instrumentType

type
    Ins2Macro* = object
        case kind*: Ins2MacroCode
        of mcStop:
            discard
        else:
            isOpen*: bool
            macType*: Ins2MacroType
            wordSize*: Ins2MacroWordSize
            data*: seq[int]
            delay*: uint8
            speed*: uint8
            loopPoint*: uint8
            releasePoint*: uint8
            mode*: uint8

    Ins2Feature* = object
        case code*: Ins2FeatureCode
        of fcGb:
            envVolume*: uint8
            envGoesUp*: bool
            envLength*: uint8
            soundLength*: uint8
            flags*: Ins2GbFlags
            hardwareSequence*: seq[string]
        of fcName:
            name*: string
        of fcMacro:
            macroList*: seq[Ins2Macro]
        of fcSample: # XXX IGNORED
            discard
        of fcNesDpcm: # XXX IGNORED
            discard
        of fcEnd:
            discard
    
    Instrument2* = ref object
        index*: int # not to be serialized!
        version*: uint16
        kind*: InstrumentType
        name*: string
        features*: seq[Ins2Feature]
