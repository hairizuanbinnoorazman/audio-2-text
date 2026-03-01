package main

import (
	"encoding/binary"
	"fmt"
	"sync"

	"github.com/gordonklaus/portaudio"
)

const (
	sampleRate = 16000
	channels   = 1
	bufferSize = 1024
)

type Recorder struct {
	stream   *portaudio.Stream
	mu       sync.Mutex
	samples  []int16
	done     chan struct{}
	ready    chan struct{} // closed when Start() finishes setup (success or failure)
	startErr error        // non-nil if Start() failed; set before closing ready
	wg       sync.WaitGroup
}

func (r *Recorder) Start() error {
	if err := portaudio.Initialize(); err != nil {
		r.startErr = fmt.Errorf("portaudio init: %w", err)
		close(r.ready)
		return r.startErr
	}

	buf := make([]int16, bufferSize)
	stream, err := portaudio.OpenDefaultStream(channels, 0, float64(sampleRate), bufferSize, buf)
	if err != nil {
		portaudio.Terminate()
		r.startErr = fmt.Errorf("open stream: %w", err)
		close(r.ready)
		return r.startErr
	}
	r.stream = stream

	if err := stream.Start(); err != nil {
		stream.Close()
		portaudio.Terminate()
		r.startErr = fmt.Errorf("start stream: %w", err)
		close(r.ready)
		return r.startErr
	}

	r.wg.Add(1)
	go func() {
		defer r.wg.Done()
		for {
			select {
			case <-r.done:
				return
			default:
				if err := stream.Read(); err != nil {
					fmt.Println("PortAudio read error:", err)
					return
				}
				r.mu.Lock()
				r.samples = append(r.samples, buf...)
				r.mu.Unlock()
			}
		}
	}()

	close(r.ready)
	return nil
}

func (r *Recorder) Stop() ([]byte, error) {
	// Wait for Start() to finish setup before touching the stream.
	<-r.ready

	// If Start() failed, it already cleaned up — nothing for us to do.
	if r.startErr != nil {
		return nil, fmt.Errorf("recorder failed to start: %w", r.startErr)
	}

	// Signal the read goroutine to exit, then wait for it.
	close(r.done)
	r.wg.Wait()

	if err := r.stream.Stop(); err != nil {
		r.stream.Close()
		portaudio.Terminate()
		return nil, fmt.Errorf("stop stream: %w", err)
	}
	if err := r.stream.Close(); err != nil {
		portaudio.Terminate()
		return nil, fmt.Errorf("close stream: %w", err)
	}
	portaudio.Terminate()

	r.mu.Lock()
	samples := r.samples
	r.mu.Unlock()

	audioData := make([]byte, len(samples)*2)
	for i, s := range samples {
		binary.LittleEndian.PutUint16(audioData[i*2:], uint16(s))
	}

	return audioData, nil
}
