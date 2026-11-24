import Foundation

/// Curated NIST Atomic Spectra Database (ASD) visible emission lines (380-780 nm)
/// spanning noble gases, alkali/alkaline-earth metals, transition metals, and actinides.
public enum ElementCatalog {
    public static let all: [ChemicalElementSynth] = [
        ChemicalElementSynth(
            id: 1,
            symbol: "H",
            name: "Hydrogen",
            category: "Nonmetal",
            atomicMass: 1.008,
            spectralLines: [
                SpectralLine(wavelengthNm: 656.28, relativeIntensity: 1.00, label: "H-alpha"),
                SpectralLine(wavelengthNm: 486.13, relativeIntensity: 0.72, label: "H-beta"),
                SpectralLine(wavelengthNm: 434.05, relativeIntensity: 0.48, label: "H-gamma"),
                SpectralLine(wavelengthNm: 410.17, relativeIntensity: 0.30, label: "H-delta")
            ]
        ),
        ChemicalElementSynth(
            id: 2,
            symbol: "He",
            name: "Helium",
            category: "Noble Gas",
            atomicMass: 4.0026,
            spectralLines: [
                SpectralLine(wavelengthNm: 587.56, relativeIntensity: 1.00, label: "D3"),
                SpectralLine(wavelengthNm: 667.82, relativeIntensity: 0.65, label: "Red"),
                SpectralLine(wavelengthNm: 501.57, relativeIntensity: 0.55, label: "Green"),
                SpectralLine(wavelengthNm: 447.15, relativeIntensity: 0.50, label: "Blue"),
                SpectralLine(wavelengthNm: 706.52, relativeIntensity: 0.45, label: "Deep Red")
            ]
        ),
        ChemicalElementSynth(
            id: 3,
            symbol: "Li",
            name: "Lithium",
            category: "Alkali Metal",
            atomicMass: 6.94,
            spectralLines: [
                SpectralLine(wavelengthNm: 670.78, relativeIntensity: 1.00, label: "Crimson"),
                SpectralLine(wavelengthNm: 610.36, relativeIntensity: 0.48, label: "Orange"),
                SpectralLine(wavelengthNm: 460.29, relativeIntensity: 0.25, label: "Blue")
            ]
        ),
        ChemicalElementSynth(
            id: 6,
            symbol: "C",
            name: "Carbon",
            category: "Nonmetal",
            atomicMass: 12.011,
            spectralLines: [
                SpectralLine(wavelengthNm: 426.73, relativeIntensity: 0.90, label: "C II Violet"),
                SpectralLine(wavelengthNm: 658.76, relativeIntensity: 0.75, label: "C I Red"),
                SpectralLine(wavelengthNm: 505.22, relativeIntensity: 0.65, label: "C I Cyan")
            ]
        ),
        ChemicalElementSynth(
            id: 7,
            symbol: "N",
            name: "Nitrogen",
            category: "Nonmetal",
            atomicMass: 14.007,
            spectralLines: [
                SpectralLine(wavelengthNm: 500.51, relativeIntensity: 0.92, label: "N II Cyan"),
                SpectralLine(wavelengthNm: 567.96, relativeIntensity: 0.72, label: "N II Yellow-Green"),
                SpectralLine(wavelengthNm: 648.20, relativeIntensity: 0.62, label: "N II Red"),
                SpectralLine(wavelengthNm: 463.05, relativeIntensity: 0.55, label: "N II Blue")
            ]
        ),
        ChemicalElementSynth(
            id: 8,
            symbol: "O",
            name: "Oxygen",
            category: "Nonmetal",
            atomicMass: 15.999,
            spectralLines: [
                SpectralLine(wavelengthNm: 615.82, relativeIntensity: 0.85, label: "O I Orange"),
                SpectralLine(wavelengthNm: 533.07, relativeIntensity: 0.68, label: "O I Green"),
                SpectralLine(wavelengthNm: 436.83, relativeIntensity: 0.52, label: "O I Violet"),
                SpectralLine(wavelengthNm: 715.67, relativeIntensity: 0.45, label: "O I Deep Red")
            ]
        ),
        ChemicalElementSynth(
            id: 10,
            symbol: "Ne",
            name: "Neon",
            category: "Noble Gas",
            atomicMass: 20.180,
            spectralLines: [
                SpectralLine(wavelengthNm: 640.22, relativeIntensity: 1.00, label: "Ne Red-Orange"),
                SpectralLine(wavelengthNm: 585.25, relativeIntensity: 0.92, label: "Ne Yellow"),
                SpectralLine(wavelengthNm: 614.31, relativeIntensity: 0.80, label: "Ne Orange"),
                SpectralLine(wavelengthNm: 626.65, relativeIntensity: 0.75, label: "Ne Amber"),
                SpectralLine(wavelengthNm: 650.65, relativeIntensity: 0.72, label: "Ne Red"),
                SpectralLine(wavelengthNm: 703.24, relativeIntensity: 0.68, label: "Ne Deep Red"),
                SpectralLine(wavelengthNm: 540.06, relativeIntensity: 0.38, label: "Ne Green")
            ]
        ),
        ChemicalElementSynth(
            id: 11,
            symbol: "Na",
            name: "Sodium",
            category: "Alkali Metal",
            atomicMass: 22.990,
            spectralLines: [
                SpectralLine(wavelengthNm: 589.00, relativeIntensity: 1.00, label: "D2"),
                SpectralLine(wavelengthNm: 589.59, relativeIntensity: 0.95, label: "D1"),
                SpectralLine(wavelengthNm: 568.82, relativeIntensity: 0.28, label: "Yellow-Green"),
                SpectralLine(wavelengthNm: 616.07, relativeIntensity: 0.20, label: "Orange")
            ]
        ),
        ChemicalElementSynth(
            id: 12,
            symbol: "Mg",
            name: "Magnesium",
            category: "Alkaline Earth",
            atomicMass: 24.305,
            spectralLines: [
                SpectralLine(wavelengthNm: 518.36, relativeIntensity: 1.00, label: "b1"),
                SpectralLine(wavelengthNm: 517.27, relativeIntensity: 0.80, label: "b2"),
                SpectralLine(wavelengthNm: 516.73, relativeIntensity: 0.55, label: "b4"),
                SpectralLine(wavelengthNm: 470.30, relativeIntensity: 0.35, label: "Blue")
            ]
        ),
        ChemicalElementSynth(
            id: 18,
            symbol: "Ar",
            name: "Argon",
            category: "Noble Gas",
            atomicMass: 39.948,
            spectralLines: [
                SpectralLine(wavelengthNm: 415.86, relativeIntensity: 0.95, label: "Violet"),
                SpectralLine(wavelengthNm: 420.07, relativeIntensity: 0.90, label: "Indigo"),
                SpectralLine(wavelengthNm: 696.54, relativeIntensity: 0.85, label: "Deep Red"),
                SpectralLine(wavelengthNm: 451.07, relativeIntensity: 0.70, label: "Blue"),
                SpectralLine(wavelengthNm: 738.40, relativeIntensity: 0.65, label: "Far Red")
            ]
        ),
        ChemicalElementSynth(
            id: 19,
            symbol: "K",
            name: "Potassium",
            category: "Alkali Metal",
            atomicMass: 39.098,
            spectralLines: [
                SpectralLine(wavelengthNm: 404.41, relativeIntensity: 0.92, label: "Lilac 1"),
                SpectralLine(wavelengthNm: 404.72, relativeIntensity: 0.76, label: "Lilac 2"),
                SpectralLine(wavelengthNm: 693.88, relativeIntensity: 0.58, label: "Red"),
                SpectralLine(wavelengthNm: 766.49, relativeIntensity: 0.85, label: "NIR-Red")
            ]
        ),
        ChemicalElementSynth(
            id: 20,
            symbol: "Ca",
            name: "Calcium",
            category: "Alkaline Earth",
            atomicMass: 40.078,
            spectralLines: [
                SpectralLine(wavelengthNm: 422.67, relativeIntensity: 1.00, label: "g Violet"),
                SpectralLine(wavelengthNm: 616.22, relativeIntensity: 0.72, label: "Orange"),
                SpectralLine(wavelengthNm: 643.91, relativeIntensity: 0.68, label: "Red-Orange"),
                SpectralLine(wavelengthNm: 558.88, relativeIntensity: 0.52, label: "Green")
            ]
        ),
        ChemicalElementSynth(
            id: 26,
            symbol: "Fe",
            name: "Iron",
            category: "Transition Metal",
            atomicMass: 55.845,
            spectralLines: [
                SpectralLine(wavelengthNm: 438.35, relativeIntensity: 1.00, label: "d Blue"),
                SpectralLine(wavelengthNm: 404.58, relativeIntensity: 0.92, label: "Violet"),
                SpectralLine(wavelengthNm: 495.76, relativeIntensity: 0.82, label: "Cyan"),
                SpectralLine(wavelengthNm: 526.95, relativeIntensity: 0.78, label: "E2 Green"),
                SpectralLine(wavelengthNm: 532.80, relativeIntensity: 0.75, label: "Green"),
                SpectralLine(wavelengthNm: 619.16, relativeIntensity: 0.52, label: "Orange")
            ]
        ),
        ChemicalElementSynth(
            id: 29,
            symbol: "Cu",
            name: "Copper",
            category: "Transition Metal",
            atomicMass: 63.546,
            spectralLines: [
                SpectralLine(wavelengthNm: 510.55, relativeIntensity: 1.00, label: "Emerald 1"),
                SpectralLine(wavelengthNm: 521.82, relativeIntensity: 0.90, label: "Emerald 2"),
                SpectralLine(wavelengthNm: 515.32, relativeIntensity: 0.82, label: "Green"),
                SpectralLine(wavelengthNm: 578.21, relativeIntensity: 0.75, label: "Gold")
            ]
        ),
        ChemicalElementSynth(
            id: 36,
            symbol: "Kr",
            name: "Krypton",
            category: "Noble Gas",
            atomicMass: 83.798,
            spectralLines: [
                SpectralLine(wavelengthNm: 557.03, relativeIntensity: 1.00, label: "Green"),
                SpectralLine(wavelengthNm: 587.09, relativeIntensity: 0.90, label: "Yellow"),
                SpectralLine(wavelengthNm: 431.96, relativeIntensity: 0.65, label: "Violet"),
                SpectralLine(wavelengthNm: 450.24, relativeIntensity: 0.60, label: "Blue")
            ]
        ),
        ChemicalElementSynth(
            id: 38,
            symbol: "Sr",
            name: "Strontium",
            category: "Alkaline Earth",
            atomicMass: 87.62,
            spectralLines: [
                SpectralLine(wavelengthNm: 460.73, relativeIntensity: 0.95, label: "Blue"),
                SpectralLine(wavelengthNm: 640.85, relativeIntensity: 0.85, label: "Red-Orange"),
                SpectralLine(wavelengthNm: 707.01, relativeIntensity: 0.80, label: "Crimson"),
                SpectralLine(wavelengthNm: 679.10, relativeIntensity: 0.70, label: "Red")
            ]
        ),
        ChemicalElementSynth(
            id: 56,
            symbol: "Ba",
            name: "Barium",
            category: "Alkaline Earth",
            atomicMass: 137.327,
            spectralLines: [
                SpectralLine(wavelengthNm: 553.55, relativeIntensity: 1.00, label: "Apple Green"),
                SpectralLine(wavelengthNm: 493.41, relativeIntensity: 0.80, label: "Ba II Cyan"),
                SpectralLine(wavelengthNm: 614.17, relativeIntensity: 0.70, label: "Orange"),
                SpectralLine(wavelengthNm: 649.69, relativeIntensity: 0.60, label: "Red")
            ]
        ),
        ChemicalElementSynth(
            id: 80,
            symbol: "Hg",
            name: "Mercury",
            category: "Transition Metal",
            atomicMass: 200.592,
            spectralLines: [
                SpectralLine(wavelengthNm: 546.07, relativeIntensity: 1.00, label: "e Green"),
                SpectralLine(wavelengthNm: 435.83, relativeIntensity: 0.92, label: "g Blue-Violet"),
                SpectralLine(wavelengthNm: 576.96, relativeIntensity: 0.78, label: "Yellow 1"),
                SpectralLine(wavelengthNm: 579.07, relativeIntensity: 0.76, label: "Yellow 2"),
                SpectralLine(wavelengthNm: 404.66, relativeIntensity: 0.68, label: "h Violet")
            ]
        ),
        ChemicalElementSynth(
            id: 92,
            symbol: "U",
            name: "Uranium",
            category: "Actinide",
            atomicMass: 238.0289,
            spectralLines: [
                SpectralLine(wavelengthNm: 424.17, relativeIntensity: 0.95, label: "U II Violet"),
                SpectralLine(wavelengthNm: 591.54, relativeIntensity: 0.90, label: "U I Yellow"),
                SpectralLine(wavelengthNm: 502.74, relativeIntensity: 0.75, label: "Cyan-Green"),
                SpectralLine(wavelengthNm: 549.29, relativeIntensity: 0.70, label: "Green"),
                SpectralLine(wavelengthNm: 644.92, relativeIntensity: 0.65, label: "Red")
            ]
        )
    ]

    public static func element(atomicNumber z: Int) -> ChemicalElementSynth? {
        all.first(where: { $0.id == z })
    }

    public static func element(symbol: String) -> ChemicalElementSynth? {
        all.first(where: { $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame })
    }
}
