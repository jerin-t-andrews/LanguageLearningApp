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
                
                // The bubble is always visible; if loading, a white loading circle overlays it.
                AudioBubbleView(audioLevels: audioManager.levels, isLoading: audioManager.isLoading)
                    .frame(width: 120, height: 120)
                
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
                    
                    Button(action: {
                        audioManager.sendRecordingToServer()
                    }) {
                        ZStack {
                            // The black circular background.
                            Circle()
                                .fill(Color.black)
                            // The white play icon, offset as needed.
                            Image(systemName: "play.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(.white)
                                // Adjust the size of the icon so it fits well inside the button.
                                .frame(width: 60, height: 60)
                                .offset(x: 6, y: 1) // Tweak these values to nudge the icon.
                        }
                        .frame(width: 100, height: 100) // Maintains the overall button size.
                    }


                }
                .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - AudioBubbleView
struct AudioBubbleView: View {
    var audioLevels: [CGFloat]
    var isLoading: Bool
    
    // Compute an aggregate value based on the maximum audio level.
    private var scaleFactor: CGFloat {
        let level = audioLevels.max() ?? 0.1
        return 1.0 + (level - 0.1)
    }
    
    var body: some View {
        ZStack {
            // Always display the pulsating black bubble.
            Circle()
                .fill(Color.black)
                .frame(width: 100, height: 100)
                .scaleEffect(scaleFactor)
                .animation(.easeInOut(duration: 0.1), value: scaleFactor)
            
            // If loading, overlay the white loading circle.
            if isLoading {
                WhiteLoadingView()
            }
        }
    }
}

// MARK: - WhiteLoadingView (Custom White Loader)
struct WhiteLoadingView: View {
    @State private var rotation: Double = 0
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(Color.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
            .frame(width: 100, height: 100)
            .rotationEffect(Angle(degrees: rotation))
            .onAppear {
                withAnimation(Animation.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - AudioManager
class AudioManager: NSObject, ObservableObject {
    @Published var levels: [CGFloat] = Array(repeating: 0.1, count: 20)
    @Published var isLoading: Bool = false
    
    private var audioRecorder: AVAudioRecorder?
    var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private let fileName = "recording.m4a"
    
    // Start recording and update the audio levels for UI.
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
    
    // Stop recording and invalidate the timer.
    func stopRecording() {
        audioRecorder?.stop()
        timer?.invalidate()
        levels = Array(repeating: 0.1, count: 20)
        print("Recording stopped. File saved at: \(getFileURL().path)")
    }
    
    // Send the recorded file to the server, then decode, write, play, and delete the .wav file.
    func sendRecordingToServer() {
        guard let url = URL(string: "http://3.137.210.3:8000/transcribe/") else {
            print("Invalid URL")
            return
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let fileURL = getFileURL()
        guard let audioData = try? Data(contentsOf: fileURL) else {
            print("Failed to load recording data")
            DispatchQueue.main.async {
                self.isLoading = false
            }
            return
        }
        
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
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.isLoading = false
                }
                print("Upload error: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self?.isLoading = false
                }
                print("No data received from server")
                return
            }
            
            DispatchQueue.main.async {
                do {
                    let tempDirectory = FileManager.default.temporaryDirectory
                    let outputURL = tempDirectory.appendingPathComponent("output.wav")
                    try data.write(to: outputURL)
                    print("Server audio written to: \(outputURL.path)")
                    
                    self?.audioPlayer = try AVAudioPlayer(contentsOf: outputURL)
                    self?.audioPlayer?.prepareToPlay()
                    self?.audioPlayer?.play()
                    
                    self?.isLoading = false
                    print("Playing audio from file")
                } catch {
                    self?.isLoading = false
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
