type
  InstrumentType* = enum
    itStandard = 0
    itFm4Op
    itGb
    itC64
    itAmiga
    # etc. etc. etc.

  Ins2FeatureCode* = enum
    fcEnd = "EN"
    fcName = "NA"
    fcMacro = "MA"
    fcGb = "GB"
    fcSample = "SM"
    fcNesDpcm = "NE"

  Ins2GbFlag* = enum
    gbSoftwareEnvelope
    gbInitEnvelope

  Ins2GbFlags* = set[Ins2GbFlag]

  Ins2MacroCode* = enum
    mcVol = 0
    mcArp
    mcDuty
    mcWave
    mcPitch
    mcEx1
    mcEx2
    mcEx3
    mcAlg
    mcFb
    mcFms
    mcAms
    mcPanL
    mcPanR
    mcPhaseReset
    mcEx4
    mcEx5
    mcEx6
    mcEx7
    mcEx8
    mcStop = 0xff

  Ins2MacroType* = enum
    mtSequence = 0
    mtAdsr
    mtLfo

  Ins2MacroWordSize* = enum
    mwUint8 = 0
    mwInt8
    mwInt16
    mwInt32
