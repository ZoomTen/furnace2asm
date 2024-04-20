import std/tables
import ./chip
import ./instrument
import ./pattern

type
  Meta = object
    author*: string
    comment*: string
    name*: string
    version*: uint16

  TimingInfo* = object
    arpSpeed*: uint8
    clockSpeed*: float32
    highlight*: (uint8, uint8)
    speed*: (uint8, uint8)
    timeBase*: uint8
    virtualTempo*: (uint16, uint16)

  ChipInfo* = object
    kind*: ChipType
    panning*: int8
    volume*: float
    settings*: string

  ChannelInfo* = object
    abbreviation*: string
    name*: string
    collapsed*: bool
    shown*: bool
    numEffects*: uint8

  MiscInfo = object
    masterVolume*: float
    patternLength*: uint16
    tuning*: float
    extendedCompatFlags*: string
    compatFlags*: string

  Module* = ref object
    meta*: Meta
    timing*: TimingInfo
    order*: OrderedTable[int, seq[int]]
    chips*: seq[ChipInfo]
    channelInfo*: seq[ChannelInfo]
    miscInfo*: MiscInfo
    patterns*: seq[Pattern]
    instruments*: seq[Instrument2]
