## Intermediary format

import ./notes

type
    NoteSeqCommand* = object
        noteSignature*: (Note, uint16)
        length*: int
        instrument*: int16
        volume*: int16
        effects*: seq[(int16, int16)]

    NoteSeq* = seq[NoteSeqCommand]