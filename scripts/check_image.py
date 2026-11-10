# SPDX-License-Identifier: MIT
"""Read-only binary guard against the Windows 3.0 export/fixup collision."""
from pathlib import Path
import argparse
import json
import struct


EXPECTED_EXPORTS = {1, 2, 3, 4, 5, 10, 11, 12, 13, 14}
EXPECTED_WHEEL_NAMES = {'WHEELAPIVERSION': 10, 'WHEELREADDELTA': 11,
                        'WHEELLOSTPACKETS': 12, 'WHEELREADDELTAAGE': 13,
                        'WHEELSTATUS': 14}
EXPORT_PREFIX = bytes.fromhex('8cd89045558bec1e8ed85657')


def inspect_image(image):
    def read(offset, size):
        if offset < 0 or offset + size > len(image):
            raise ValueError('NE field extends beyond the file')
        return image[offset:offset + size]

    def word(offset):
        return struct.unpack('<H', read(offset, 2))[0]

    def require(condition, message):
        if not condition:
            raise ValueError(message)

    require(read(0, 2) == b'MZ', 'Missing MZ header')
    ne = struct.unpack('<I', read(0x3c, 4))[0]
    require(read(ne, 2) == b'NE', 'Missing NE header')
    nw = lambda offset: word(ne + offset)
    require(nw(0x0c) & 0x8001 == 0x8001, 'Expected a single-data DLL')
    require(not nw(0x0c) & 0x2000, 'NE image has the linker-error flag')
    require(nw(0x1e) == 0 and nw(0x10) == 0, 'Expected no imports or heap')
    require(nw(0x3e) <= 0x0300, 'Expected Windows 3.0 compatibility')
    segments = []
    for index in range(nw(0x1c)):
        sector, size, flags, minimum = struct.unpack(
            '<4H', read(ne + nw(0x22) + index * 8, 8))
        length = (size or 65536) if sector else 0
        offset = sector << nw(0x32)
        require(flags & 0x40 and not flags & 0x1010,
                'All driver segments must be fixed, preload, non-discardable')
        if length:
            read(offset, length)
        segments.append(dict(offset=offset, length=length, flags=flags,
                             minimum=minimum))
    require(len(segments) == 2 and nw(0x0e) == 2,
            'Expected fixed code and combined DGROUP data/BSS segments')

    entries = {}
    position = ne + nw(4)
    end = position + nw(6)
    ordinal = 1
    while position < end:
        count, segment = read(position, 2)
        position += 2
        if not count:
            break
        if not segment:
            ordinal += count
            continue
        require(segment <= len(segments), 'Expected fixed segment entries')
        for _ in range(count):
            flags = read(position, 1)[0]
            offset = word(position + 1)
            position += 3
            entries[ordinal] = dict(segment=segment, offset=offset, flags=flags)
            ordinal += 1
    require(set(entries) == EXPECTED_EXPORTS, 'Unexpected driver export ordinals')

    def read_names(position, end):
        names = []
        while position < end:
            length = read(position, 1)[0]
            position += 1
            if not length:
                return names
            require(position + length + 2 <= end, 'NE name exceeds its table')
            name = read(position, length).decode('ascii')
            ordinal = word(position + length)
            names.append(dict(name=name, ordinal=ordinal))
            position += length + 2
        raise ValueError('Unterminated NE name table')

    nonresident = struct.unpack('<I', read(ne + 0x2c, 4))[0]
    export_names = read_names(ne + nw(0x26), ne + nw(0x28))
    export_names += read_names(nonresident, nonresident + nw(0x20))
    named_ordinals = {item['name']: item['ordinal'] for item in export_names}
    for name, ordinal in EXPECTED_WHEEL_NAMES.items():
        require(named_ordinals.get(name) == ordinal,
                'Missing uppercase wheel API export %s at ordinal %d' % (name, ordinal))
    for ordinal, entry in entries.items():
        require(entry['segment'] == 1 and entry['flags'] & 3 == 3,
                'Export %d must use fixed code and public-data prologue patching' % ordinal)
        offset = segments[0]['offset'] + entry['offset']
        prefix = read(offset, len(EXPORT_PREFIX))
        require(prefix == EXPORT_PREFIX,
                'Export %d needs MOV AX,DS; NOP and the standard far frame' % ordinal)
        entry['prefix'] = prefix.hex()

    relocations = []
    for index, segment in enumerate(segments):
        if not segment['flags'] & 0x100:
            continue
        position = segment['offset'] + segment['length']
        count = word(position)
        for item in range(count):
            address_type, kind, offset, target, target_offset = struct.unpack(
                '<BBHHH', read(position + 2 + item * 8, 8))
            relocations.append(dict(segment=index + 1, address_type=address_type,
                                    kind=kind, offset=offset, target=target,
                                    target_offset=target_offset))
    # Both interrupt entry points establish DS independently. WEP calls the
    # exported Disable routine through one internal far-address relocation.
    require(len(relocations) == 3, 'Expected two DS fixups and one WEP call')
    selectors = [r for r in relocations if r['address_type'] == 2]
    calls = [r for r in relocations if r['address_type'] == 3]
    require(len(selectors) == 2 and len(calls) == 1, 'Unexpected relocation types')
    code = segments[0]
    for relocation in relocations:
        require(relocation['segment'] == 1 and relocation['kind'] == 0,
                'Expected internal, non-additive code relocation')
        offset = relocation['offset']
        for ordinal, entry in entries.items():
            require(not entry['offset'] <= offset < entry['offset'] + len(EXPORT_PREFIX),
                    'Relocation overlaps export %d prologue' % ordinal)
    for relocation in selectors:
        require(relocation['target'] == 2, 'DS fixup must target DGROUP')
        offset = relocation['offset']
        require(read(code['offset'] + offset - 1, 5) == bytes.fromhex('b8ffff8ed8'),
                'DS fixup must terminate its chain and load DS')
    call = calls[0]
    require(call['target'] == 1 and call['target_offset'] == entries[3]['offset'],
            'WEP must call Disable')
    require(read(code['offset'] + call['offset'] - 1, 1) == b'\x9a',
            'Expected immediate far CALL')
    return dict(status='PASS', bytes=len(image),
                module_flags=nw(0x0c), autodata=nw(0x0e), heap=nw(0x10),
                imports=nw(0x1e), segments=segments, exports=entries,
                export_names=export_names, relocations=relocations)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('driver', nargs='?', type=Path,
                        default=Path(__file__).with_name('WHEEL.DRV'))
    args = parser.parse_args()
    print(json.dumps(inspect_image(args.driver.read_bytes()), indent=2))
