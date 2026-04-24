import Foundation

enum Storage {
    static let baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
}
