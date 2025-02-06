import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var audioLevels: [CGFloat] = Array(repeating: 0.1, count: 20)
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
                        audioManager.playRecording()
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

struct AudioWaveView: View {
    var audioLevels: [CGFloat]
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 5) {
                ForEach(audioLevels.indices, id: \ .self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.black)
                        .frame(width: 8, height: geometry.size.height * (0.2 + audioLevels[index] * 1.2))
                        .animation(Animation.easeInOut(duration: 0.1), value: audioLevels[index])
                }
            }
            .frame(height: geometry.size.height)
        }
    }
}

class AudioManager: ObservableObject {
    @Published var levels: [CGFloat] = Array(repeating: 0.1, count: 20)
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private let fileName = "recording.m4a"
    
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
    
    func stopRecording() {
        audioRecorder?.stop()
        timer?.invalidate()
        levels = Array(repeating: 0.1, count: 20)
        print("Recording stopped. File saved at: \(getFileURL().path)")
    }
    
    func playRecording() {
        sendRecordingToServer()
        let url = getFileURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            print("Audio file does not exist at path: \(url.path)")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            print("Playing audio from: \(url.path)")
        } catch {
            print("Failed to play recording: \(error.localizedDescription)")
        }
    }
    
    private func sendRecordingToServer() {
        let url = URL(string: "TEMPORARYURL")! // HERE IS WHERE THE URL GOES
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let fileURL = getFileURL()
        guard let audioData = try? Data(contentsOf: fileURL) else {
            print("Failed to load recording data")
            return
        }
        
        var body = Data()
        let filename = "recording.m4a"
        let mimetype = "audio/m4a"
        
        body.append("--\(boundary)
".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"
".data(using: .utf8)!)
        body.append("Content-Type: \(mimetype)

".data(using: .utf8)!)
        body.append(audioData)
        body.append("
".data(using: .utf8)!)
        body.append("--\(boundary)--
".data(using: .utf8)!)
        
        request.httpBody = body
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Upload error: \(error.localizedDescription)")
            } else {
                print("Audio uploaded successfully")
            }
        }.resume()
    }
    
    private func getFileURL() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = paths[0].appendingPathComponent(fileName)
        return fileURL
    }
}
