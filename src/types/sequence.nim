## Intermediary format

import ./notes

type
  NoteSignature* = tuple[note: Note, octave: uint16]

  NoteSeqCommand* = object
    noteSignature*: NoteSignature
    length*: int
    instrument*: int16
    volume*: int16
    effects*: seq[(int16, int16)]

  NoteSeq* = seq[NoteSeqCommand]
