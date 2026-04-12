# Audio

## Rules

### Rule: Normalize Audio Levels First
- **Applies to:** All content
- **Rule:** Balance all voice levels to similar loudness before applying any processing or effects.
- **Reasoning:** Normalized levels create a professional listening experience and provide a stable foundation for downstream processing like compression and limiting to work effectively.

### Rule: Remove Non-Essential Filler Sounds
- **Applies to:** All content
- **Rule:** Remove breaths, clicks, background noise, and other sounds that don't contribute to the story or energy of the piece.
- **Reasoning:** Clean audio feels more professional and keeps the listener focused on the message rather than distracted by unintended sounds.

### Rule: Apply Professional Audio Chain in Correct Order
- **Applies to:** Podcasts and interviews
- **Rule:** Chain audio processing in this sequence: Gate → Compressor (1176 style) → De-esser → Noise Reduction → EQ → Limiter.
- **Reasoning:** This order ensures each processor works on optimally prepared audio from the previous stage—gates cut microphone bleed, compressors control dynamics, de-essers address sibilance, and limiters protect against peaks.

### Rule: Use Gate for Multi-Person Recordings
- **Applies to:** Multi-speaker content
- **Rule:** Use a gate to cut microphone bleed by allowing only full-volume sounds through, preventing off-camera chatter or ambient noise from leaking into individual tracks.
- **Reasoning:** Gates keep each speaker isolated to their own microphone, resulting in cleaner dialogue and easier mixing in multi-person recordings.

### Rule: De-Ess All Spoken Content
- **Applies to:** All spoken content
- **Rule:** Apply a de-esser to reduce harsh "S" sounds in speech.
- **Reasoning:** Harsh sibilance causes listener discomfort and can be distracting; de-essing maintains clarity while making dialogue pleasant to listen to.

### Rule: Shape Voice Presence with EQ
- **Applies to:** All spoken content
- **Rule:** Apply a high-pass filter at 80Hz to remove rumble and add subtle boosts around 3kHz for presence.
- **Reasoning:** This removes low-frequency noise that muddies dialogue while adding clarity and presence to make speech feel natural and engaging.

### Rule: Protect Against Peak Distortion with Master Limiter
- **Applies to:** All content
- **Rule:** Set a master limiter (L1 Maximizer style) with threshold between -4 to -6dB to catch unexpected peaks.
- **Reasoning:** Even well-normalized audio can have sudden spikes that cause distortion; a limiter acts as a final safety net without audibly affecting normal levels.

### Rule: Sync Audio via Clap or Spoken Spike
- **Applies to:** Multi-camera content
- **Rule:** Find a clap, snap, or spoken phrase that creates a visible spike on all microphones and use that as the sync point.
- **Reasoning:** Audio waveforms provide precise visual reference points for synchronization across multiple cameras and microphone sources.

### Rule: Replace Camera Audio with Dedicated Microphone
- **Applies to:** All content
- **Rule:** Always replace camera-mounted microphone audio with audio from dedicated microphones recorded separately.
- **Reasoning:** Dedicated microphones capture significantly better audio quality than built-in camera mics, which are distant, have poor frequency response, and pick up more room noise.

### Rule: Link Audio and Video Tracks After Syncing
- **Applies to:** All multi-camera content
- **Rule:** Group and link audio and video tracks together after syncing so they move as a single unit during editing.
- **Reasoning:** Linked tracks prevent accidental sync drift and make editing more efficient by ensuring audio and video stay locked together through cuts and transitions.

### Rule: Use Music to Add Subliminal Storytelling
- **Applies to:** All content
- **Rule:** Choose music that conveys emotion or information not already being communicated through the video, operating on a subliminal level.
- **Reasoning:** Music that simply duplicates what's already visible feels redundant; the best music adds a layer of emotional or informational depth that enriches the viewing experience.

### Rule: Music Sets Tone and Expectations
- **Applies to:** All content
- **Rule:** Recognize that music establishes the vibe and sets expectations for what the viewer will experience next.
- **Reasoning:** The right music can prime the audience emotionally and prepare them psychologically for the content that follows, creating a cohesive viewing journey.

### Rule: Keep Music Stings Short and Professional
- **Applies to:** All content
- **Rule:** Use short music stings and transitions lasting 1–5 seconds for professional polish.
- **Reasoning:** Brief, well-placed music moments feel intentional and crafted; longer stings without purpose feel amateurish and disrupt pacing.

### Rule: Avoid Extended Music Passages
- **Applies to:** All content
- **Rule:** Never let music run longer than 20–30 seconds or it begins to feel like filler or an advertisement.
- **Reasoning:** Prolonged music without context distracts from the core message and feels like padding rather than purposeful storytelling.

### Rule: Target Loudness Standards by Platform
- **Applies to:** Platform-specific distribution
- **Rule:** Master to -16 LUFS for podcasts and -14 LUFS for social media clips.
- **Reasoning:** Different platforms and playback contexts have different loudness targets; matching these ensures consistent volume levels across distribution channels.

### Rule: Remove Filler Words Strategically
- **Applies to:** Podcasts and interviews
- **Rule:** Always remove um, uh, er, ah, and hmm; conditionally remove like, you know, and basically based on context and speaker style.
- **Reasoning:** Filler words distract listeners and make speakers sound less confident, but some words are tied to natural speech patterns and removing all of them creates robotic dialogue.

### Rule: Control Silence Between Speakers and Within Speech
- **Applies to:** Podcasts and dialogue-heavy content
- **Rule:** Keep silence between speakers at maximum 0.5 seconds and within a single speaker at maximum 0.3 seconds, with exceptions for dramatic pauses up to 0.8 seconds.
- **Reasoning:** Proper silence duration maintains conversational pacing and energy while allowing moments of dramatic weight when intentional.

### Rule: Preserve Natural Pauses
- **Applies to:** All spoken content
- **Rule:** Never remove all pauses from speech—doing so makes dialogue sound robotic and unnatural.
- **Reasoning:** Pauses are essential to natural speech rhythm, emphasis, and comprehension; complete removal disconnects the audio from human communication patterns.

### Rule: Adjust Speech Speed Based on Delivery Rate
- **Applies to:** Podcasts and interviews
- **Rule:** Speed up speech based on words-per-minute: below 120 WPM increase to 1.15x, 120–130 WPM increase to 1.08x, 130–160 WPM leave unchanged.
- **Reasoning:** Slower speakers benefit from slight acceleration without becoming unnatural, while faster speakers maintain clarity at normal speed.

### Rule: Capture Good Audio at Source
- **Applies to:** All content
- **Rule:** Invest in good microphones and proper recording technique at the source, just as you would with color grading and lighting.
- **Reasoning:** The principle applies across all production—80% of quality work happens in camera; trying to fix poor source audio in post is always more difficult than capturing it well initially.

### Rule: Account for Microphone Impedance Differences
- **Applies to:** Multi-camera content
- **Rule:** Recognize that different camera microphones have different impedance characteristics and use dedicated audio tracks for consistent, superior quality.
- **Reasoning:** Mixing camera mics with varying impedance creates frequency mismatches and tonal inconsistencies; dedicated microphones eliminate these variables and ensure sonic cohesion.

## Tips

- **Invest in source quality:** Professional audio starts with good microphones and proper mic placement. You cannot fix poor source material, so spend time getting it right in production.

- **Use automation for natural dynamics:** Instead of heavy compression, automate volume levels to maintain natural breath and emphasis while keeping dialogue at consistent perceived loudness.

- **Trust your ears but verify with meters:** Loudness perception is subjective and context-dependent. Always cross-reference your ears with loudness metering tools (LUFS meters) to ensure consistency.

- **Create audio snapshots before destructive edits:** Before removing filler sounds, ums, or breaths, duplicate the track and save an unedited version as backup in case you need to recover removed material.

- **Use spectral analysis to identify and remove noise:** Tools like iZotope RX let you visualize and surgically remove specific noise frequencies (hum, buzz, rumble) without affecting dialogue.

- **Leave headroom for mixing and mastering:** Mix at -3dB to -6dB below the limiter threshold to give yourself room to blend multiple elements without hitting the ceiling.

- **Create marker-based edit points:** Mark each filler word, breath, or click with a colored marker before removing to ensure precision and give yourself a visual roadmap of what needs attention.

- **Test on multiple playback systems:** Listen back on headphones, studio monitors, phone speakers, and car audio to ensure your mix translates across different listening environments.
