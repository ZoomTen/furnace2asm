type ChipType* = enum
  # insert more chip types here
  chEnd = 0
  chGb = 4

func numChannels*(chip: ChipType): int =
  case chip
  of chGb:
    result = 4
  else:
    discard
