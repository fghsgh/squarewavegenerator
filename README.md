# squarewavegenerator
Lua wave/sound generator with multiple waveshapes, volume, sliding and duty cycle support (v0.4)

A multifunctional wave/sound generator with multiple waveshapes, volume, sliding and duty cycle support for Lua 5.2.

## Installation
Just put the file `squarewavegenerator.lua` in any directory for scripts and run it with Lua 5.2.

## Documentation
A shorter documentation can be found as a comment at the beginning of the program file. That one may be out of date though.

You can import the output of this into Audacity like this:
- `File` -> `Import` -> `Raw data...`
- Choose the file
- `Encoding` = `32-bit float` (unless you specified PCM, in that case it's `Signed 16-bit PCM`
- `Byte order` = `Little-endian` (unless you specified big-endianness, in that case it's `Big-endian`)
- `Channels` = `1 Channel (Mono)`
- `Start offset` = `0` bytes
- `Amount to import` = `100`%
- `Sample rate` = `44100` or any other sample rate you specified.

You can add any number of arguments, which can in turn take their own (fixed number of) arguments. This is a list of all possible arguments:
- `outputfile <file>` or `output <file>` or `of <file>`: this specifies the output file. Output will be in a raw 32-bit float (IEEE754) audio format (a WAV without header). If this is not given, output is sent to stdout. A warning is displayed in that case.
- `mplayer` or `play`: this disables any output file and sends it to MPlayer through a pipe instead. The correct arguments are automatically passed to mplayer to make sure it understands the raw audio format. A warning is displayed. MPlayer may still write anything to stdout or stderr, although the `-really-quiet` option is sent. MPlayer must be installed for this to work, of course, and your computer must be fast enough to keep up with the generator.
- `mplayeroptions <options>`: sets the options to be sent to MPlayer. This implies `mplayer`. `<options>` must be a single argument, but multiple arguments (to MPlayer) may be specified by using spaces inside of it. Specifying this multiple times will add more options instead of overwriting the previous ones.
- `quiet` or `q`: this suppresses the output of all questions (but still reads the answers from stdin) and the warning at the beginning (`output will be to stdout/played to mplayer`).
- `noprogress` or `np`: this suppresses the output of the progress bar. Otherwise, it would output something like\
`sample x/x (x%)` every second.
- `nointeractive` or `ni`: doesnt' ask any questions while running. All default values are assumed if not supplied from the command-line.
- `samplerate <rate>` or `sr <rate>`: sets the samplerate. This defaults to `44100`. This value is passed to MPlayer if required.
- `gain <gain>` or `g <gain>`: sets the global gain. Every sample's value is multiplied by this.
- `endian <little|big>`: either `little` or `big`, defaults to `little`. This is forced to `little` if playing through MPlayer. All samples will be written in reverse order if this is `big`.
- `pcm`: use 16-bit signed PCM instead of 32-bit float for output. This is implied if playing through MPlayer.
- `wave <number> <property> <value>` or `w <number> <property> <value>`: sets the given property of the given wave to the given value. If this wave didn't exist before, it will be created. Any empty fields will be completed with default values. The wave identifier (number) is unrelated to the one shown when asking for input interactively.
- if anything else is found, an error message is shown to the user

These are all possible wave properties:
- `starttime` or `start`: the sample when this wave starts. You can use `s` as a suffix for seconds instead of samples. This defaults to 1.
- `endtime` or `end`: the sample when this wave ends. You can use `s` as a suffic for seconds instead of samples. This defaults to the largest already specified `endtime` (for another wave), or to 1s after `starttime` if this is the first wave.
- `volumestart` or `volstart` or `vol`: the volume at the beginning of the wave. This defaults to 1.
- `volumeend` or `volend`: the volume at the end of the wave. This defaults to whatever `volumestart` was.
- `volumeramp` or `volramp`: how to go from `volumestart` to `volumeend` if they are different. This can be `lin` for linear, `exp` for exponential, or a mathematical function in `x` (with the entire `math` library passed as `_ENV`) (x is 0 to 1 and the result is also expected to be between 0 and 1)
- `shape`: this can be one of
  - `sine`: a sine wave, this is the default
  - `square`: a square wave with variable duty cycle
  - `sawtooth`: a sawtooth wave
  - `triangle`: a triangle wave
  - `noise`: white noise using `math.random()`
- `frequencystart` or `freqstart` or `freq`: the beginning frequency of the tone. This defaults to `440`.\
You can also specify a MIDI note name like `A4` or `C#3`. The whole syntax of that is: `A-G` (upper/lower case), any number of `#` and `b`, the octave number. The behaviour for any other syntax is undefined. `A4` is 440 Hz.
- `frequencyend` or `freqend`: the ending frequency of the tone. This defaults to `frequencystart`.
- `frequencyramp` or `freqramp`: how to go from `frequencystart` to `frequencyend` if they are different. This behaves similarily to `volumeramp`.
- `dutystart` or `duty`: the duty cycle of the square wave, only applies if this wave is in fact a square wave. This should be a number between `0` and `1` and it defaults to `.5`.
- `dutyend`: the duty cycle at the end of the square wave. This defaults to `dutystart`.
- `dutyramp`: how the duty cycle changes during the square wave. This syntax is similar to `volumeramp`.

In interactive mode, the following questions are asked in this order, unless they are specified as command-line arguments or if `no interactive` mode is on. The default will be given for every question. Enter an empty line (just press enter) to choose the default.
- `samplerate`
- `gain`
- `endian`
- the number of wave events that will be supplied from stdin
- for each wave:
  - `volumestart`
  - `volumeend`
  - if `volumestart` and `volumeend` are not equal:
    - `volumeramp`
  - `shape`
  - if `shape` is not `noise`:
    - `frequencystart`
    - `frequencyend`
    - if `frequencystart` and `frequencyend` are not equal:
      - `frequencyramp`
  - if `shape` is `square`:
    - `dutystart`
    - `dutyend`
    - if `dutystart` and `dutyend` are not equal:
      - `dutyramp`

## Examples
- `squarewavegenerator mplayer ni np q w 1 freq A4`: play A4 for one second through MPlayer with no other output
- `squarewavegenerator of wave.raw ni np q w 1 freq C4 w 2 freq E4 w 3 freq G4 g .3`: generate a chord and save it to file `wave.raw`, the gain is lowered to avoid clipping.
- `squarewavegenerator sr 44100 g 1 w 1 shape noise w 1 volstart .1 w 1 volend 1 w 2 freqstart C6 w 2 freqend C2 w 2 freqramp exp w 2 endtime 5s w 1 endtime 10s > wave.raw`: set sample rate to `44100`, gain to `1`, define some noise that gets louder from `.1` to `1` during `10` seconds and a glissando from a `C2` to a `C6` that lasts `5` seconds. Then, ask the user for more notes. Finally, render everything to the file `wave.raw` through a stdout pipe.
- `squarewavegenerator`: get everything from stdin
- this plays the C scale (of course you would make something like this with a script):
```
squarewavegenerator \
w 1 start 0s w 1 end 1s w 1 freq C4 \
w 2 start 1s w 2 end 2s w 2 freq D4 \
w 3 start 2s w 3 end 3s w 3 freq E4 \
w 4 start 3s w 4 end 4s w 4 freq F4 \
w 5 start 4s w 5 end 5s w 5 freq G4 \
w 6 start 5s w 6 end 6s w 6 freq A4 \
w 7 start 6s w 7 end 7s w 7 freq B4 \
w 8 start 7s w 8 end 8s w 8 freq C5 \
mplayer ni np q
```
- `squarewavegenerator mplayer q np sr 44100 g 1`: for scripts; do not write to stdout/stderr and only take note data from stdin
- `squarewavegenerator mplayer ni np q w 1 freq 440 w 2 freq 660 g .5`: two notes mean that you should lower the gain to avoid clipping
- `squarewavegenerator ni w 1 shape square w 1 duty .5 w 1 freqramp 'cos(7*2*pi*x)/2 - .125*abs(x-.5)^(1/5)*((x-.5)/abs(x-.5))' w 1 end 1323000 w 1 freqstart G5 w 1 freqend C6 mplayer`: plays an ambulance noise, including approximated Doppler-effect
