package main

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/transcribestreaming"
	"github.com/aws/aws-sdk-go-v2/service/transcribestreaming/types"
)

const (
	chunkSize          = 16 * 1024 // 16KB chunks
	transcribeTimeout  = 120 * time.Second
	transcribeLanguage = "en-US"
)

type Transcriber struct {
	client *transcribestreaming.Client
}

func NewTranscriber(ctx context.Context) (*Transcriber, error) {
	for _, env := range []string{"AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_REGION"} {
		if os.Getenv(env) == "" {
			return nil, fmt.Errorf("required environment variable %s is not set", env)
		}
	}

	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, fmt.Errorf("load AWS config: %w", err)
	}

	client := transcribestreaming.NewFromConfig(cfg)
	return &Transcriber{client: client}, nil
}

func (t *Transcriber) Transcribe(ctx context.Context, audioData []byte) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, transcribeTimeout)
	defer cancel()

	resp, err := t.client.StartStreamTranscription(ctx, &transcribestreaming.StartStreamTranscriptionInput{
		LanguageCode:         types.LanguageCodeEnUs,
		MediaEncoding:        types.MediaEncodingPcm,
		MediaSampleRateHertz: int32Ptr(sampleRate),
	})
	if err != nil {
		return "", fmt.Errorf("start transcription stream: %w", err)
	}

	stream := resp.GetStream()

	go func() {
		defer stream.Close()
		for offset := 0; offset < len(audioData); offset += chunkSize {
			end := offset + chunkSize
			if end > len(audioData) {
				end = len(audioData)
			}
			err := stream.Send(ctx, &types.AudioStreamMemberAudioEvent{
				Value: types.AudioEvent{
					AudioChunk: audioData[offset:end],
				},
			})
			if err != nil {
				fmt.Println("Error sending audio chunk:", err)
				return
			}
		}
	}()

	var transcripts []string
	for event := range stream.Events() {
		switch ev := event.(type) {
		case *types.TranscriptResultStreamMemberTranscriptEvent:
			for _, result := range ev.Value.Transcript.Results {
				if result.IsPartial {
					continue
				}
				for _, alt := range result.Alternatives {
					if alt.Transcript != nil {
						transcripts = append(transcripts, *alt.Transcript)
					}
				}
			}
		}
	}

	if err := stream.Err(); err != nil {
		return "", fmt.Errorf("transcription stream error: %w", err)
	}

	text := strings.TrimSpace(strings.Join(transcripts, " "))
	if text == "" {
		return "", fmt.Errorf("no speech detected in audio")
	}

	return text, nil
}

func int32Ptr(v int) *int32 {
	i := int32(v)
	return &i
}
