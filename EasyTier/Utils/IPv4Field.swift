import SwiftUI

struct IPv4Field: View {
    @Binding var ipAddress: String
    var length: Binding<String>?
    var disabledLengthEdit: Bool
    
    @FocusState private var focusedField: Int?
    @State private var octets: [String] = ["", "", "", ""]
    
    init(ip: Binding<String>, length: Binding<String>? = nil, disabledLengthEdit: Bool = false) {
        self._ipAddress = ip
        self.length = length
        self.disabledLengthEdit = disabledLengthEdit
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                ipTextField(index: index)
                
                if index < 3 {
                    Text(".")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 1)
                        .padding(.bottom, 2)
                }
            }
            
            if let lengthBinding = length {
                Text("/")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 2)
                
                TextField("32", text: Binding(
                    get: { lengthBinding.wrappedValue },
                    set: { processLengthInput($0, binding: lengthBinding) }
                ))
                .disabled(disabledLengthEdit)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 40)
                .focused($focusedField, equals: 4)
            }
        }
        .onAppear {
            syncOctetsFromExternal()
        }
        .onChange(of: ipAddress) { newValue in
            if octets.joined(separator: ".") != newValue {
                syncOctetsFromExternal()
            }
        }
    }
    
    private func ipTextField(index: Int) -> some View {
        TextField("0", text: Binding(
            get: { octets[index] },
            set: { processOctetInput(oldValue: octets[index], newValue: $0, at: index) }
        ))
        .keyboardType(index < 3 ? .decimalPad : .numberPad)
        .multilineTextAlignment(.center)
        .frame(minWidth: 30, maxWidth: 45)
        .focused($focusedField, equals: index)
    }
    
    private func processOctetInput(oldValue: String, newValue: String, at index: Int) {
        if oldValue == newValue { return }
        
        if length != nil && newValue.contains("/") {
            if newValue.count > 4 {
                parseAndDistribute(fullString: newValue)
                return
            }
            if !octets[index].isEmpty {
                octets[index] = newValue.replacingOccurrences(of: "/", with: "")
                updateIPBinding()
                focusedField = 4
                return
            }
        }
        
        if newValue.contains(".") {
            if newValue.split(separator: ".").count > 1 {
                parseAndDistribute(fullString: newValue)
                return
            }
            if !octets[index].isEmpty && index < 3 {
                octets[index] = newValue.replacingOccurrences(of: ".", with: "")
                updateIPBinding()
                focusedField = index + 1
                return
            }
        }
        
        let filtered = newValue.filter { "0123456789".contains($0) }
        
        if filtered.isEmpty && !octets[index].isEmpty {
            octets[index] = ""
            updateIPBinding()
            if index > 0 { focusedField = index - 1 }
            return
        }
        
        if let num = Int(filtered) {
            octets[index] = String(max(min(num, 255), 0))
            
            if filtered.count >= 3 {
                focusedField = index + 1
            }
            updateIPBinding()
        }
    }
    
    private func processLengthInput(_ newValue: String, binding: Binding<String>) {
        if newValue.isEmpty && !binding.wrappedValue.isEmpty {
            binding.wrappedValue = ""
            focusedField = 3
            return
        }
        
        let filtered = newValue.filter { "0123456789".contains($0) }
        
        if let num = Int(filtered) {
            binding.wrappedValue = String(max(min(num, 32), 0))
        } else if filtered.isEmpty {
            binding.wrappedValue = ""
        }
    }
    
    private func updateIPBinding() {
        self.ipAddress = octets.map {
            if let num = Int($0) {
                String(max(min(num, 255), 0))
            } else { "" }
        }.joined(separator: ".")
    }
    
    private func syncOctetsFromExternal() {
        let parts = ipAddress.split(separator: ".")
        for (i, part) in parts.enumerated() {
            if i < 4 { octets[i] = String(part) }
        }
        if ipAddress.isEmpty {
            octets = ["", "", "", ""]
        }
    }
    
    private func parseAndDistribute(fullString: String) {
        let components = fullString.split(separator: "/")
        
        if components.count > 0 {
            let ipPart = String(components[0])
            let validIpChars = ipPart.filter { "0123456789.".contains($0) }
            self.ipAddress = validIpChars
            
            let parts = validIpChars.split(separator: ".").map {
                if let num = Int($0) {
                    String(max(min(num, 255), 0))
                } else { "" }
            }
            for (i, part) in parts.enumerated() {
                if i < 4 { octets[i] = String(part.prefix(3)) }
            }
        }
        
        if let lengthBinding = length, components.count > 1 {
            let lengthPart = String(components[1]).prefix(2)
            if let num = Int(lengthPart) {
                lengthBinding.wrappedValue = String(max(min(num, 32), 0))
            }
        }
        
        if components.count > 1 && length != nil {
            focusedField = 4
        } else {
            focusedField = 3
        }
    }
}
