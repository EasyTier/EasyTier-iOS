func normalizeCIDR(_ cidr: String) -> RunningIPv4CIDR? {
    guard var cidrStruct = RunningIPv4CIDR(from: cidr) else { return nil }
    cidrStruct.address = ipv4MaskedSubnet(cidrStruct)
    return cidrStruct
}

func cidrToSubnetMask(_ cidr: Int) -> String? {
    guard cidr >= 0 && cidr <= 32 else { return nil }
    
    let mask: UInt32 = cidr == 0 ? 0 : UInt32.max << (32 - cidr)
    
    let octet1 = (mask >> 24) & 0xFF
    let octet2 = (mask >> 16) & 0xFF
    let octet3 = (mask >> 8) & 0xFF
    let octet4 = mask & 0xFF
    
    return "\(octet1).\(octet2).\(octet3).\(octet4)"
}

func ipv4MaskedSubnet(_ cidr: RunningIPv4CIDR) -> RunningIPv4Addr {
    let mask: UInt32 = cidr.networkLength == 0 ? 0 : UInt32.max << (32 - cidr.networkLength)
    return RunningIPv4Addr(addr: cidr.address.addr & mask)
}

func ipv4SubnetsOverlap(bigger: RunningIPv4CIDR, smaller: RunningIPv4CIDR) -> Bool {
    if bigger.networkLength > smaller.networkLength {
        return ipv4SubnetsOverlap(bigger: smaller, smaller: bigger)
    }
    let mask: UInt32 = bigger.networkLength == 0 ? 0 : UInt32.max << (32 - bigger.networkLength)
    return (bigger.address.addr & mask) == (smaller.address.addr & mask)
}
