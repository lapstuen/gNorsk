import SwiftUI
import UIKit

extension View {
    // Begrenser en Mac Catalyst-sheet til det tilgjengelige arealet appvinduet
    // FAKTISK har akkurat nå, i stedet for å gjette en margin ut fra full
    // skjermoppløsning. macOS har allerede plassert appens eget vindu korrekt
    // innenfor synlig skrivebord (utenom menylinje/Dock/tittellinje), så vi bruker
    // det vinduets nåværende størrelse (UIWindow.bounds) som et konkret, verifisert
    // tak — ikke en antatt margin.
    //
    // VIKTIG: min/ideal/max settes til SAMME klemmede verdi. Systemet bruker
    // idealHeight/idealWidth (ikke maxHeight/maxWidth) til å avgjøre selve
    // vindusstørrelsen — hvis ideal fikk stå urørt på det ønskede (uklemte) tallet,
    // ble vinduet fortsatt bedt om full størrelse uansett skjermstørrelse, og havnet
    // delvis utenfor skjermen (både topp og bunn kunne kuttes samtidig).
    func catalystSheetFrame(width: CGFloat, height: CGFloat) -> some View {
        let available = Self.currentWindowBounds()
        // Liten buffer til selve sheet-vinduets egen tittellinje.
        let chromeBuffer: CGFloat = 40

        let clampedWidth = min(width, available.width - chromeBuffer)
        let clampedHeight = min(height, available.height - chromeBuffer)

        return self.frame(
            minWidth: clampedWidth,
            idealWidth: clampedWidth,
            maxWidth: clampedWidth,
            minHeight: clampedHeight,
            idealHeight: clampedHeight,
            maxHeight: clampedHeight
        )
    }

    // Størrelsen på appens eget nøkkelvindu akkurat nå — dette er allerede
    // garantert å ligge innenfor synlig skrivebord, siden macOS selv la det der.
    private static func currentWindowBounds() -> CGRect {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        if let keyWindow = windows.first(where: { $0.isKeyWindow }) ?? windows.first {
            return keyWindow.bounds
        }
        return UIScreen.main.bounds
    }
}
