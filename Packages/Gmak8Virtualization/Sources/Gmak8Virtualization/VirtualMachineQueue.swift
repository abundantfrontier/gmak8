import Foundation

public enum VirtualMachineQueue {
    public static let label = "dev.gmak8.vm"

    public static let shared = DispatchQueue(label: label)
}
