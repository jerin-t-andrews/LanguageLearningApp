import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var audioLevels: [CGFloat] = Array(repeating: 0.1, count: 20)
    @State private var isListening = false
    @ObservedObject private var audioManager = AudioManager()
    
    var body: some View {
        ZStack {
            Color(hex: "FAF3D1")
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                
                AudioWaveView(audioLevels: audioLevels)
                    .frame(height: 100)
                    .padding(.horizontal, 75) // Moves waveform away from edges
                    .onReceive(audioManager.$levels) { levels in
                        self.audioLevels = levels
                    }
                
                Spacer()
                
                Button(action: {
                    if isListening {
                        audioManager.stopListening()
                    } else {
                        audioManager.startListening()
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
                        .frame(width: 8, height: geometry.size.height * (0.2 + audioLevels[index] * 1.2)) // More exaggerated wave
                        .animation(Animation.easeInOut(duration: 0.1).repeatForever(autoreverses: true), value: audioLevels[index])
                }
            }
            .frame(height: geometry.size.height)
        }
    }
}

class AudioManager: ObservableObject {
    @Published var levels: [CGFloat] = Array(repeating: 0.1, count: 20)
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    
    func startListening() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
        ]
        
        let url = URL(fileURLWithPath: "/dev/null")
        audioRecorder = try? AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.record()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.audioRecorder?.updateMeters()
            self.levels = (0..<20).map { _ in pow(10, CGFloat(self.audioRecorder?.averagePower(forChannel: 0) ?? -60) / 20) } // Exponential scaling for dynamic waves
        }
    }
    
    func stopListening() {
        audioRecorder?.stop()
        timer?.invalidate()
        levels = Array(repeating: 0.1, count: 20)
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var hexNumber: UInt64 = 0
        
        if scanner.scanHexInt64(&hexNumber) {
            let r = Double((hexNumber & 0xFF0000) >> 16) / 255.0
            let g = Double((hexNumber & 0x00FF00) >> 8) / 255.0
            let b = Double(hexNumber & 0x0000FF) / 255.0
            self.init(red: r, green: g, blue: b)
        } else {
            self.init(white: 0.0)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
