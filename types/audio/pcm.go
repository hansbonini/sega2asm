package audio

import "os"

func init() { RegisterEncoder(pcmEncoder{}) }

type pcmEncoder struct{}

func (pcmEncoder) Name() string { return "wav" }
func (pcmEncoder) Ext() string  { return ".wav" }

// Encode writes raw 8-bit unsigned mono PCM data as a standard WAV file.
func (pcmEncoder) Encode(data []byte, path string, sampleRate int) error {
	sampleRate = NormalizeSampleRate(sampleRate)
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()

	if err := WriteWAVHeader(f, uint32(len(data)), sampleRate); err != nil {
		return err
	}
	_, err = f.Write(data)
	return err
}
