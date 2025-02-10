import SwiftUI
import AVFoundation

// MARK: - Model for Decoding JSON Response

struct TranscriptionResponse: Codable {
    let transcription: String
    let response_text: String
    let audio_base64: String
}

// MARK: - ContentView

struct ContentView: View {
    @State private var isListening = false
    @StateObject private var audioManager = AudioManager()
    
    var body: some View {
        ZStack {
            Color(red: 250/255, green: 243/255, blue: 209/255)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                
                AudioWaveView(audioLevels: audioManager.levels)
                    .frame(height: 100)
                    .padding(.horizontal, 75)
                
                Spacer()
                
                HStack(spacing: 20) {
                    // Record Button
                    Button(action: {
                        if isListening {
                            audioManager.stopRecording()
                        } else {
                            audioManager.startRecording()
                        }
                        isListening.toggle()
                    }) {
                        Image(systemName: isListening ? "mic.fill" : "mic.slash.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 70, height: 70)
                            .padding()
                            .background(Color.black)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    
                    // Play Button triggers sending the recording to the server
                    // and then plays the returned audio (.wav file).
                    Button(action: {
                        audioManager.sendRecordingToServer()
                    }) {
                        Image(systemName: "play.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 70, height: 70)
                            .padding()
                            .background(Color.black)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                }
                .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - AudioWaveView

struct AudioWaveView: View {
    var audioLevels: [CGFloat]
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 5) {
                ForEach(audioLevels.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.black)
                        .frame(width: 8, height: geometry.size.height * (0.2 + audioLevels[index] * 1.2))
                        .animation(.easeInOut(duration: 0.1), value: audioLevels[index])
                }
            }
            .frame(height: geometry.size.height)
        }
    }
}

// MARK: - AudioManager

class AudioManager: NSObject, ObservableObject {
    @Published var levels: [CGFloat] = Array(repeating: 0.1, count: 20)
    
    private var audioRecorder: AVAudioRecorder?
    var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private let fileName = "recording.m4a"  // Local recording file name
    
    // Start recording and update the audio levels for UI
    func startRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
        ]
        
        let url = getFileURL()
        print("Recording will be saved at: \(url.path)")
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
        } catch {
            print("Failed to start recording: \(error.localizedDescription)")
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.audioRecorder?.updateMeters()
            DispatchQueue.main.async {
                self.levels = (0..<20).map { _ in
                    let power = self.audioRecorder?.averagePower(forChannel: 0) ?? -60
                    return CGFloat(max(0.1, min(1.0, (Double(power) + 60) / 60)))
                }
            }
        }
    }
    
    // Stop recording and invalidate the timer
    func stopRecording() {
        audioRecorder?.stop()
        timer?.invalidate()
        levels = Array(repeating: 0.1, count: 20)
        print("Recording stopped. File saved at: \(getFileURL().path)")
    }
    
    // Send the locally recorded file to the server, then decode, write, play, and delete the .wav file.
    func sendRecordingToServer() {
        // Set up the backend URL.
        guard let url = URL(string: "http://127.0.0.1:8000/transcribe/") else {
            print("Invalid URL")
            return
        }
        
        // Configure the URLRequest.
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Set up a unique boundary for the multipart/form-data request.
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Get the local m4a file URL and load its data.
        let fileURL = getFileURL()
        guard let audioData = try? Data(contentsOf: fileURL) else {
            print("Failed to load recording data")
            return
        }
        
        // Build the multipart/form-data payload.
        var body = Data()
        let filename = "recording.m4a"
        let mimetype = "audio/m4a"
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimetype)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        // Create the URLSession data task.
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("Upload error: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No data received from server")
                return
            }
            
            // Since the backend returns a WAV file directly, we write the binary data to a temporary file.
            DispatchQueue.main.async {
                do {
                    // Save the received WAV data to a temporary file.
                    let tempDirectory = FileManager.default.temporaryDirectory
                    let outputURL = tempDirectory.appendingPathComponent("output.wav")
                    try data.write(to: outputURL)
                    print("Server audio written to: \(outputURL.path)")
                    
                    // Initialize and configure the AVAudioPlayer.
                    self?.audioPlayer = try AVAudioPlayer(contentsOf: outputURL)
                    self?.audioPlayer?.prepareToPlay()
                    self?.audioPlayer?.play()
                    print("Playing audio from file")
                } catch {
                    print("Error handling audio data: \(error.localizedDescription)")
                }
            }
        }.resume()
    }


    // Helper to get the local file URL for the recorded audio.
    private func getFileURL() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent(fileName)
    }
}

// MARK: - AVAudioPlayerDelegate Implementation

extension AudioManager: AVAudioPlayerDelegate {
    // Once playback finishes, delete the temporary .wav file.
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let tempDirectory = FileManager.default.temporaryDirectory
        let outputURL = tempDirectory.appendingPathComponent("output.wav")
        do {
            try FileManager.default.removeItem(at: outputURL)
            print("Temporary .wav file deleted from local storage.")
        } catch {
            print("Failed to delete temporary .wav file: \(error.localizedDescription)")
        }
    }
}
