#ifndef OVERLAY_UI_H
#define OVERLAY_UI_H

void initNSApplication(void);
void setupOverlay(void);
void showOverlay(void);
void hideOverlay(void);
int isOverlayVisible(void);
char *getTranscriptionText(void);
void updateTranscriptionText(const char *text);
void updateStatusLabel(const char *text);
void stopWaveform(void);

#endif
