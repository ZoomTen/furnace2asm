Furnace2Asm 0.1.5
=================

A tool to convert Furnace project files into files for use with the pret
Pokémon disassemblies.

Why does this exist again?
--------------------------

Because Furnace is very streamlined and actually emulates a Game Boy
(what I hear would be very close to what I get).

I also want to nostalgia-mine, so that’s why the GUI looks the way it
is. Kino mid-00s GBA binary hacking aesthetics. Thanks to Ward’s wNim
library, I don’t need to deal with VB6 just to make that possible lmao.

Examples
--------

Examples can be found in the ``examples`` folder in the repo:
https://github.com/ZoomTen/furnace2asm.

Compatibility
-------------

What is **not supported** and will either be rejected by the tool,
ignored or have unpredictable results:

-  Projects created with versions **below** 0.6pre2. If you’ve got an
   older project, simply open and re-save it in the newer version.
-  Projects containing setups other than **1× Game Boy**.
-  Instruments other than the dedicated Game Boy instruments.
-  Panning using ``80xx``. Use the ``08xy`` effect instead.
-  Manual vibrato using ``04xy``.
-  Subsongs.
-  ``EDxx``. If you wanted triplets, sorry about that.
-  Macros other than duty cycle patterns (read further on). For volume
   control, only the dedicated Game Boy envelope editing features are
   supported.
-  Setting a single duty cycle, panning, etc. from macros. Use the
   ``12xx``, ``08xy``, etc. effects instead. In Furnace, there is a
   limit of 8 effect slots for any given channel, so there’s plenty of
   room there.
-  Note and macro release (``===`` and ``REL`` respectively). Use note
   cuts (``OFF``) instead.

Setting the volume column *is* supported, although the volume changes
will currently not persist across patterns.

By default, notes longer than 16 rows will be split into multiple notes
covering the entire span of the original note, e.g. 24-row note = length
16 + length 8.

What you **should do** to ensure your project is converted properly:

-  When cutting a pattern short, have a ``0D00`` effect on **all
   channels**, not just one of them.
-  If you want your track to loop, use a single ``0Bxx`` effect in the entire composition, and ensure
   that it is at the end of the track.
-  Omit the ``0Bxx`` effect if you do not want your track to loop.
-  Name the song in the Song Info tab. This will be used for the labels
   and constant names, e.g. ``Cinna bar island`` will be converted to
   ``CinnaBarIsland`` and ``CINNA_BAR_ISLAND``.
-  Determine explicitly what to do with notes longer than 16 rows (do
   you want to tie multiple notes together or to cut?)

List of supported effects:

-  ``08xy``: Channel panning.
-  ``10xx``: Change waveform.
-  ``12xx``: Change duty cycle.
-  ``E5xx``: Pitch offset, where normal tuning is ``xx = 80``.

Additional effects supported when enabling Pokemon Prism engine output:

-  ``00xy``: Arpeggio
-  ``01xx``: Pitch slide up. Ensure “Pitch Linearity” (under
   Compatibility Flags) is set to “Linear” for a 1:1 output.
-  ``02xx``: Pitch slide down. Ensure “Pitch Linearity” (under
   Compatibility Flags) is set to “Linear” for a 1:1 output.

Duty cycle pattern effects are supported through the use of the
Duty/Noise macro. This macro **must** have a length of 4.

Noise channel instructions
--------------------------

The noise channel conversion works like this: Notes are ignored, instead
it’s **instrument numbers**. The tool does not currently support mapping
these instrument numbers to drum set numbers from the get-go, but
constants will be made for you so you can edit them in yourself.
Example:

::

   ; Drum constants, replace with the proper values
   DRUM_WILD_BATTLE_04        EQU     C_
   DRUM_WILD_BATTLE_02        EQU     C_
   DRUM_WILD_BATTLE_0C        EQU     C_
   DRUM_WILD_BATTLE_01        EQU     C_
   DRUM_WILD_BATTLE_09        EQU     C_
   DRUM_WILD_BATTLE_08        EQU     C_

   ; Drumset to use, replace with the proper value
   DRUMSET_WILD_BATTLE        EQU     $00

The ``DRUM_WILD_BATTLE_*`` constants correspond to instrument numbers in
your song, so ``DRUM_WILD_BATTLE_0C`` would refer to instrument ``0C``.

The ``DRUMSET_*`` constant should refer to which drumset number you want
to use. The tool only works with drums in the song that are all part of
the same drumset, so choose your drumset wisely before working on
percussion.