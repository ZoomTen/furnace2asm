import ./notes

type
    Row* = object
        note*: Note
        octave*: uint16
        instrument*: int16
        volume*: int16
        effects*: seq[(int16, int16)]

    Pattern* = object
        channel*: uint16
        index*: uint16
        name*: string
        rows*: seq[Row]