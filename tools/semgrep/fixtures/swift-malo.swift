// Formas que las reglas de swift.yaml DEBEN cazar. Una por regla.
// Cada línea lleva el id que la caza, para que el test compruebe cobertura.
import Foundation

func casosMalos(_ data: Data, _ any: Any) throws {
    let a = try! JSONDecoder().decode(String.self, from: data)   // swift-force-try
    let b = any as! String                                        // swift-force-cast
    print("depurando \(a) \(b)")                                  // swift-print-en-produccion
    DispatchQueue.main.async { }                                  // swift-gcd-legado
    Thread.sleep(forTimeInterval: 1)                              // swift-thread-sleep
    let lock = NSLock()                                           // swift-primitivas-de-lock-manuales
    lock.lock()
}
