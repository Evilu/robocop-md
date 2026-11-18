"""Write a one-entry MAME software list so MAME loads a ROM with the Sega (SSF2) mapper.

usage: md_softlist.py <rom.md> <out dir>
Creates <out dir>/hash/megadriv.xml and <out dir>/roms/rcmd/<rom name>; run MAME with
  mame genesis rcmd -hashpath <out dir>/hash -rompath <out dir>/roms
MAME only enables bank switching for cartridges its software list marks with a mapper.
rom_titan is the Krikzz SSF mapper (32 banks); rom_ssf2 implements only 10.
"""
import hashlib
import shutil
import sys
import zlib
from pathlib import Path


def main(rom, out):
    rom, out = Path(rom), Path(out)
    data = rom.read_bytes()
    (out / 'hash').mkdir(parents=True, exist_ok=True)
    dest = out / 'roms' / 'rcmd'
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(rom, dest / rom.name)
    area = 1 << (len(data) - 1).bit_length()
    (out / 'hash' / 'megadriv.xml').write_text(f'''<?xml version="1.0"?>
<!DOCTYPE softwarelist SYSTEM "softwarelist.dtd">
<softwarelist name="megadriv" description="RoboCop MD test builds">
	<software name="rcmd">
		<description>RoboCop MD (test build)</description>
		<year>2026</year>
		<publisher>test</publisher>
		<part name="cart" interface="megadriv_cart">
			<feature name="slot" value="rom_titan"/>
			<dataarea name="rom" width="16" endianness="big" size="{area}">
				<rom name="{rom.name}" size="{len(data)}" crc="{zlib.crc32(data):08x}" sha1="{hashlib.sha1(data).hexdigest()}" offset="0"/>
			</dataarea>
		</part>
	</software>
</softwarelist>
''')


if __name__ == '__main__':
    main(*sys.argv[1:3])
