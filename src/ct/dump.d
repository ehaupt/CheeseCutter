/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module ct.dump;

import ct.base;
import com.util;
import std.file;
import std.string;
import std.stdio;

private const string byteOp = "!byte", wordOp = "!word";
private int highestChord, highestCmd, highestInstr,
	highestPulse, highestFilter, highestWave;

// ugly hack
private int getHighestUsed(ubyte[] array) {
	for(size_t i = array.length - 1; i >= 0; i--) {
		if(array[i] > 0)
			return cast(int)i;
	}
	return -1;
}

private void initTabLengths(Song sng) {
	sng.seqIterator((Sequence seq, Element e) {
			if(e.instr.hasValue() &&
			   highestInstr < e.instr.value) {
				highestInstr = e.instr.value;
			}
			if(e.cmd.value > 0) {
				if(e.cmd.value < 0x40) {
					if(highestCmd < (e.cmd.value & 0x1f)) {
						highestCmd = e.cmd.value;
					}
				}
				else if(e.cmd.value < 0x60) {
					if(highestPulse < (e.cmd.value & 0x1f)) {
						highestPulse = e.cmd.value & 0x1f;
					}
				}
				else if(e.cmd.value < 0x80) {
					if(highestFilter < (e.cmd.value & 0x1f)) {
						highestFilter = e.cmd.value & 0x1f;
					}
				}
				else if(e.cmd.value < 0xa0) {
					if(highestChord < (e.cmd.value & 0x1f)) {
						highestChord = e.cmd.value & 0x1f;
					}
				}
			}
		});

	for(int i = 0; i < highestInstr; i++) {
		int waveptr = sng.getWavetablePointer(i);
		if(waveptr > highestWave) {
			highestWave = waveptr;
		}
		int pulseptr = sng.getPulsetablePointer(i);
		if(pulseptr > highestPulse) {
			highestPulse = pulseptr;
		}
		int filtptr = sng.getFiltertablePointer(i);
		if(filtptr > highestFilter) {
			highestFilter = filtptr;
		}
	}

	highestChord++;
	highestCmd++;
	highestInstr++;
	highestPulse++;
	highestFilter++;
	highestWave++;
	
	for(int i = 255; i >= highestWave; i--) {
		if(sng.wave1Table[i] == 0x7e ||
		   sng.wave1Table[i] == 0x7f) {
			if(sng.wave2Table[i] > i)
				throw new UserException("Overflow in wave table");
			highestWave = i;
			break;
		}
	}

	// TO TEST: make last pulsetable entry point > current row
	for(int i = 256 - 4; i > 0; i -= 4) {
		int pptr = sng.pulseTable[i + 3];
		if(pptr < 0x40 && pptr > highestPulse) {
			highestPulse = pptr;
		}
		if(pptr == 0x7f) {
			highestPulse = i / 4;
			break;
		}
	}
	// TO TEST: make last filtertable entry point > current row
	for(int i = 256 - 4; i > 0; i -= 4) {
		int fptr = sng.filterTable[i + 3];
		if(fptr < 0x40 && fptr > highestPulse) {
			highestFilter = fptr;
		}
		if(fptr == 0x7f) {
			highestFilter = i / 4;
			break;
		}
	}

	// TODO: add code to test table overflows
	
	highestPulse++;
	highestFilter++;
}

		
string dumpData(Song sng, string title) {
	string output;

	initTabLengths(sng);
	
	void append(string s) {
		output ~= s;
	}

	void hexdump(ubyte[] buf, int rowlen) {
		int c;
		append("\t\t" ~ byteOp ~ " ");
		foreach(i, b; buf) {
			append(format("$%02x", b));
			c++;
			if(c >= rowlen) {
				c = 0;
				if(i < buf.length - 1)
					append("\n\t\t" ~ byteOp ~ " ");
			}
			else if(i < buf.length - 1) append(",");
		}
		append("\n");
	}


	int tablen;
	ushort[][] trackpointers = new ushort[][sng.subtunes.numOf];
	sng.subtunes.activate(0);
	auto packedTracks = sng.subtunes.compact();	
	
	append( "arp1 = *\n");
	hexdump(sng.wave1Table[0 .. highestWave], 16);
	append( "arp2 = *\n");
	hexdump(sng.wave2Table[0 .. highestWave], 16);
	append( "filttab = *\n");
	hexdump(sng.filterTable[0 .. highestFilter * 4], 4);
	append( "pulstab = *\n");
	hexdump(sng.pulseTable[0 .. highestPulse * 4], 4);
	append( "inst = *\n");
	ubyte[512] instab = 0;

	for(int i = 0; i < 8; i++) {
		append( format("\ninst%d = *\n",i));
		hexdump(sng.instrumentTable[i * 48 .. i * 48 + highestInstr], 8);
	}

	append( "\nseqlo = *\n\t\t!8 ");
	for(int i = 0; i < sng.numOfSeqs; i++) {
		append(format("<s%02x", i));
		if(i < sng.numOfSeqs - 1)
			append(",");
	}
	append( "\nseqhi = *\n\t\t!8 ");
	for(int i = 0; i < sng.numOfSeqs; i++) {
		append(format(">s%02x", i));
		if(i < sng.numOfSeqs - 1)
			append(",");
	}

	//tablen = getHighestUsed(sng.superTable[0..64]) + 1;
	//if(tablen < 1) tablen = 1;
	if(highestCmd < 1) highestCmd = 1;
	
	append( "\ncmd1 = *\n");
	hexdump(sng.superTable[0 .. highestCmd], 16);
	append( "cmd2 = *\n");
	hexdump(sng.superTable[64 .. 64 + highestCmd], 16);
	append( "cmd3 = *\n");
	hexdump(sng.superTable[128 .. 128 + highestCmd], 16);

	// dump songsets

	append( "songsets = *\n");
	for(int i = 0; i < sng.subtunes.numOf; i++) {
		append(wordOp ~ "\t");
		for(int voice = 0; voice < 3; voice++) {
			if(voice > 0)
				append(",");
			append(" " ~ format("track%d_%d", i, voice));
		}
		append( format("\n\t\t" ~ byteOp ~ " %d, 7\n", sng.songspeeds[i]));
	}
	// dump tracks
	foreach(i, ref subtune; packedTracks) {
		foreach(j, voice; subtune) {
			append(format("track%d_%d = *\n", i, j));
			hexdump(voice, 16);
		}
	}

	for(int i = 0; i < sng.numOfSeqs; i++) {
		append( format("s%02x = *\n", i));
		Sequence s = sng.seqs[i];
		hexdump(s.compact(), 16);
	}

	// TODO: rewrite to use indextable
	tablen = getHighestUsed(sng.chordTable) + 1;
	append("\nchord = *\n");
	if(tablen < 1) tablen = 1;
	hexdump(sng.chordTable[0 .. tablen], 16);
	append("\nchordindex = *\n");
	hexdump(sng.chordIndexTable[0 .. highestChord], 16);
	writeln(output);
	return output;
}
