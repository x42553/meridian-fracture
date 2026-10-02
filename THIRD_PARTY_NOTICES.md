# Third-party notices

Meridian Fracture's own code and data are released under the MIT License (see [LICENSE](LICENSE); this is a placeholder choice and the project owner may change it). This file lists everything else that is shipped in, or was used to build, the game.

## Summary

| Component | Where | Licence | Shipped |
|---|---|---|---|
| Godot Engine 4.7.2 (and the third-party libraries inside it) | the game executable | MIT | yes |
| Rajdhani (Indian Type Foundry) | `game/assets/fonts/rajdhani` | SIL OFL 1.1 | yes |
| Orbitron (The Orbitron Project Authors) | `game/assets/fonts/orbitron` | SIL OFL 1.1 | yes |
| Share Tech Mono (Carrois Type Design, Ralph du Carrois) | `game/assets/fonts/share_tech_mono` | SIL OFL 1.1 | yes |
| Kokoro-82M text-to-speech model and voices (hexgrad) | generated the announcer and unit-response speech at build time | Apache-2.0 | no, only its generated audio |
| kokoro-onnx 0.4.7, onnxruntime 1.30.0 | build-time tools | MIT | no |
| numpy, soundfile, Pillow | build-time audio and image tools | BSD-3-Clause, BSD-3-Clause, HPND | no |
| libsndfile, libvorbis | encoding of the Ogg Vorbis files | LGPL-2.1, BSD-3-Clause | no (the encoded files are shipped) |
| espeak-ng, phonemizer-fork (pulled in by kokoro-onnx) | grapheme-to-phoneme at build time | GPL-3.0-or-later | no |
| Piper (piper-tts), voices en_US-joe and en_GB-cori | optional fast-iteration renderer, its output is never in the shipped set | GPL-3.0-or-later (tool), CC0-1.0 (voices) | no |

## All art and audio are generated

- **3D models and effects** are procedural: each unit, structure and effect is a small JSON recipe (`game/data/recipes`) that the game compiles into meshes at run time. There are no imported models, textures or images from third parties.
- **Sound effects, ambience and music** are synthesised by `tools/py/audio` (numpy, fixed seeds). Nothing is recorded and no third-party sample is used.
- **Announcer and unit-response speech** is text-to-speech generated offline with Kokoro-82M (Apache-2.0). The generated audio is licensed with the project. The espeak-ng and phonemizer-fork tools that Kokoro pulls in are GPL-3.0-or-later; they run only on the machine that builds the audio, are not linked into the game, are not shipped, and the generated audio is not a derivative of them. Voices whose licences restrict commercial use (macOS `say`, Piper `hfc_male`, `ryan`, `lessac`) are never used.
- Per-file provenance (generator, model, voice, text, licences, tool versions and SHA-256) is in `game/assets/audio/provenance.json`; the shipped credit line is `game/assets/audio/NOTICE.txt`; the toolchain notice is `tools/py/audio/NOTICE.txt`.

## Godot Engine

Meridian Fracture is built with the Godot Engine (https://godotengine.org). The exported game contains the engine runtime, which itself includes third-party libraries (for example ENet, FreeType, HarfBuzz, libvorbis, zlib and others); their licences are listed in Godot's `COPYRIGHT.txt` (https://github.com/godotengine/godot/blob/master/COPYRIGHT.txt) and in the engine's Help > About > Third-party licenses.

```
Copyright (c) 2014-present Godot Engine contributors.
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Fonts (SIL Open Font License 1.1)

The three typefaces are used unmodified. Each licence text is vendored next to its font file as `OFL.txt`. Copyright lines:

- **Rajdhani**: Copyright (c) 2014, Indian Type Foundry (info@indiantypefoundry.com).
- **Orbitron**: Copyright 2018 The Orbitron Project Authors (https://github.com/theleagueof/orbitron), with Reserved Font Name "Orbitron".
- **Share Tech Mono**: Copyright (c) 2012, Carrois Type Design, Ralph du Carrois (post@carrois.com www.carrois.com), with Reserved Font Name "Share".

The licence text, identical for all three:

```
This license is copied below, and is also available with a FAQ at:
http://scripts.sil.org/OFL


-----------------------------------------------------------
SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
-----------------------------------------------------------

PREAMBLE
The goals of the Open Font License (OFL) are to stimulate worldwide
development of collaborative font projects, to support the font creation
efforts of academic and linguistic communities, and to provide a free and
open framework in which fonts may be shared and improved in partnership
with others.

The OFL allows the licensed fonts to be used, studied, modified and
redistributed freely as long as they are not sold by themselves. The
fonts, including any derivative works, can be bundled, embedded, 
redistributed and/or sold with any software provided that any reserved
names are not used by derivative works. The fonts and derivatives,
however, cannot be released under any other type of license. The
requirement for fonts to remain under this license does not apply
to any document created using the fonts or their derivatives.

DEFINITIONS
"Font Software" refers to the set of files released by the Copyright
Holder(s) under this license and clearly marked as such. This may
include source files, build scripts and documentation.

"Reserved Font Name" refers to any names specified as such after the
copyright statement(s).

"Original Version" refers to the collection of Font Software components as
distributed by the Copyright Holder(s).

"Modified Version" refers to any derivative made by adding to, deleting,
or substituting -- in part or in whole -- any of the components of the
Original Version, by changing formats or by porting the Font Software to a
new environment.

"Author" refers to any designer, engineer, programmer, technical
writer or other person who contributed to the Font Software.

PERMISSION & CONDITIONS
Permission is hereby granted, free of charge, to any person obtaining
a copy of the Font Software, to use, study, copy, merge, embed, modify,
redistribute, and sell modified and unmodified copies of the Font
Software, subject to the following conditions:

1) Neither the Font Software nor any of its individual components,
in Original or Modified Versions, may be sold by itself.

2) Original or Modified Versions of the Font Software may be bundled,
redistributed and/or sold with any software, provided that each copy
contains the above copyright notice and this license. These can be
included either as stand-alone text files, human-readable headers or
in the appropriate machine-readable metadata fields within text or
binary files as long as those fields can be easily viewed by the user.

3) No Modified Version of the Font Software may use the Reserved Font
Name(s) unless explicit written permission is granted by the corresponding
Copyright Holder. This restriction only applies to the primary font name as
presented to the users.

4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
Software shall not be used to promote, endorse or advertise any
Modified Version, except to acknowledge the contribution(s) of the
Copyright Holder(s) and the Author(s) or with their explicit written
permission.

5) The Font Software, modified or unmodified, in part or in whole,
must be distributed entirely under this license, and must not be
distributed under any other license. The requirement for fonts to
remain under this license does not apply to any document created
using the Font Software.

TERMINATION
This license becomes null and void if any of the above conditions are
not met.

DISCLAIMER
THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM
OTHER DEALINGS IN THE FONT SOFTWARE.
```

## Kokoro-82M (Apache-2.0)

The Kokoro-82M weights and voices (hexgrad/Kokoro-82M, v1.0) are licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0). They are not distributed with the game; the game ships only audio that the model generated. The model files are downloaded at build time into `.cache/tts` and never committed.

## Other build-time tools

numpy and soundfile (BSD-3-Clause), libvorbis (BSD-3-Clause), Pillow (HPND), libsndfile (LGPL-2.1, used dynamically through soundfile), kokoro-onnx and onnxruntime (MIT). None of these is part of the shipped game. See `tools/py/audio/NOTICE.txt` for the details and the Piper voice policy.
