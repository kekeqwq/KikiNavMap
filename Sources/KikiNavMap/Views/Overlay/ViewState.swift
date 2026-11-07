import SwiftUI

/// Select the stable State property wrapper in type context. SDK 27 also
/// exports a same-named macro requiring proprietary SwiftUIMacros plugins.
public typealias ViewState<Value> = SwiftUI.State<Value>
