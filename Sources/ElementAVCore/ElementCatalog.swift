import Foundation

/// Complete 118-element IUPAC Periodic Table catalog with NIST Atomic Spectra Database (ASD)
/// visible emission lines (380-780 nm) for experimentally characterized elements (Z = 1...99)
/// and relativistic visible emission bands for synthetic transactinides (Z = 100...118).
public enum ElementCatalog {
    public static let categories: [String] = [
        "All",
        "Nonmetal",
        "Noble Gas",
        "Alkali Metal",
        "Alkaline Earth",
        "Metalloid",
        "Halogen",
        "Post-Transition Metal",
        "Transition Metal",
        "Lanthanide",
        "Actinide"
    ]

    private typealias LineRow = (nm: Double, rel: Double, label: String?)
    private typealias ElementRow = (z: Int, sym: String, name: String, cat: String, mass: Double, lines: [LineRow])

    /// All 118 elements ordered by atomic number (Z = 1...118).
    public static let all: [ChemicalElementSynth] = {
        let rows: [ElementRow] =
            periods1To3 +
            period4 +
            period5 +
            period6Main +
            lanthanides +
            period7Main +
            actinides

        return rows
            .sorted { $0.z < $1.z }
            .map { row in
                ChemicalElementSynth(
                    id: row.z,
                    symbol: row.sym,
                    name: row.name,
                    category: row.cat,
                    atomicMass: row.mass,
                    spectralLines: row.lines.map { line in
                        SpectralLine(
                            wavelengthNm: line.nm,
                            relativeIntensity: line.rel,
                            label: line.label
                        )
                    }
                )
            }
    }()

    public static func element(atomicNumber z: Int) -> ChemicalElementSynth? {
        all.first(where: { $0.id == z })
    }

    public static func element(symbol: String) -> ChemicalElementSynth? {
        all.first(where: { $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame })
    }

    public static func filtered(query: String, category: String = "All") -> [ChemicalElementSynth] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { el in
            let matchesCategory = (category == "All" || el.category == category)
            guard matchesCategory else { return false }
            guard !trimmed.isEmpty else { return true }
            if let zQuery = Int(trimmed), el.id == zQuery {
                return true
            }
            return el.name.localizedCaseInsensitiveContains(trimmed)
                || el.symbol.localizedCaseInsensitiveContains(trimmed)
                || el.category.localizedCaseInsensitiveContains(trimmed)
        }
    }

    // MARK: - Periods 1 to 3 (Z = 1...18)

    private static let periods1To3: [ElementRow] = [
        (1, "H", "Hydrogen", "Nonmetal", 1.008, [
            (656.28, 1.00, "H-alpha"), (486.13, 0.72, "H-beta"),
            (434.05, 0.48, "H-gamma"), (410.17, 0.30, "H-delta")
        ]),
        (2, "He", "Helium", "Noble Gas", 4.0026, [
            (587.56, 1.00, "D3"), (667.82, 0.65, "Red"), (501.57, 0.55, "Green"),
            (447.15, 0.50, "Blue"), (706.52, 0.45, "Deep Red")
        ]),
        (3, "Li", "Lithium", "Alkali Metal", 6.94, [
            (670.78, 1.00, "Crimson"), (610.36, 0.48, "Orange"), (460.29, 0.25, "Blue")
        ]),
        (4, "Be", "Beryllium", "Alkaline Earth", 9.0122, [
            (457.27, 0.90, "Be I Blue"), (467.33, 0.85, "Be II Blue"), (527.08, 0.60, "Be II Green")
        ]),
        (5, "B", "Boron", "Metalloid", 10.81, [
            (412.19, 0.85, "B II Violet"), (494.04, 0.75, "B II Cyan"), (547.60, 1.00, "Flame Green")
        ]),
        (6, "C", "Carbon", "Nonmetal", 12.011, [
            (426.73, 0.90, "C II Violet"), (658.76, 0.75, "C I Red"), (505.22, 0.65, "C I Cyan")
        ]),
        (7, "N", "Nitrogen", "Nonmetal", 14.007, [
            (500.51, 0.92, "N II Cyan"), (567.96, 0.72, "N II Yellow-Green"),
            (648.20, 0.62, "N II Red"), (463.05, 0.55, "N II Blue")
        ]),
        (8, "O", "Oxygen", "Nonmetal", 15.999, [
            (615.82, 0.85, "O I Orange"), (533.07, 0.68, "O I Green"),
            (436.83, 0.52, "O I Violet"), (715.67, 0.45, "O I Deep Red")
        ]),
        (9, "F", "Fluorine", "Halogen", 18.998, [
            (685.60, 1.00, "F I Red"), (690.25, 0.82, "F I Deep Red"),
            (739.87, 0.70, "F I Far Red"), (623.97, 0.55, "F I Orange")
        ]),
        (10, "Ne", "Neon", "Noble Gas", 20.180, [
            (640.22, 1.00, "Ne Red-Orange"), (585.25, 0.92, "Ne Yellow"),
            (614.31, 0.80, "Ne Orange"), (626.65, 0.75, "Ne Amber"),
            (650.65, 0.72, "Ne Red"), (703.24, 0.68, "Ne Deep Red"), (540.06, 0.38, "Ne Green")
        ]),
        (11, "Na", "Sodium", "Alkali Metal", 22.990, [
            (589.00, 1.00, "D2"), (589.59, 0.95, "D1"),
            (568.82, 0.28, "Yellow-Green"), (616.07, 0.20, "Orange")
        ]),
        (12, "Mg", "Magnesium", "Alkaline Earth", 24.305, [
            (518.36, 1.00, "b1"), (517.27, 0.80, "b2"), (516.73, 0.55, "b4"), (470.30, 0.35, "Blue")
        ]),
        (13, "Al", "Aluminum", "Post-Transition Metal", 26.982, [
            (396.15, 1.00, "Al I Violet"), (394.40, 0.82, "Al I Deep Violet"),
            (466.30, 0.64, "Al II Blue"), (624.34, 0.45, "Al II Orange")
        ]),
        (14, "Si", "Silicon", "Metalloid", 28.085, [
            (390.55, 0.95, "Si I Violet"), (634.71, 1.00, "Si II Red-Orange"),
            (637.14, 0.82, "Si II Red"), (505.60, 0.68, "Si II Cyan")
        ]),
        (15, "P", "Phosphorus", "Nonmetal", 30.974, [
            (604.31, 0.92, "P II Orange"), (542.59, 0.85, "P II Green"),
            (460.21, 0.72, "P II Blue"), (529.61, 0.65, "P II Emerald")
        ]),
        (16, "S", "Sulfur", "Nonmetal", 32.06, [
            (545.38, 1.00, "S II Green"), (564.00, 0.82, "S II Yellow-Green"),
            (469.41, 0.70, "S I Blue"), (675.72, 0.58, "S I Red")
        ]),
        (17, "Cl", "Chlorine", "Halogen", 35.45, [
            (479.45, 1.00, "Cl II Blue"), (481.01, 0.86, "Cl II Cyan-Blue"),
            (542.32, 0.72, "Cl II Green"), (725.66, 0.60, "Cl I Red")
        ]),
        (18, "Ar", "Argon", "Noble Gas", 39.948, [
            (415.86, 0.95, "Violet"), (420.07, 0.90, "Indigo"), (696.54, 0.85, "Deep Red"),
            (451.07, 0.70, "Blue"), (738.40, 0.65, "Far Red")
        ])
    ]

    // MARK: - Period 4 (Z = 19...36)

    private static let period4: [ElementRow] = [
        (19, "K", "Potassium", "Alkali Metal", 39.098, [
            (404.41, 0.92, "Lilac 1"), (404.72, 0.76, "Lilac 2"),
            (693.88, 0.58, "Red"), (766.49, 0.85, "NIR-Red")
        ]),
        (20, "Ca", "Calcium", "Alkaline Earth", 40.078, [
            (422.67, 1.00, "g Violet"), (616.22, 0.72, "Orange"),
            (643.91, 0.68, "Red-Orange"), (558.88, 0.52, "Green")
        ]),
        (21, "Sc", "Scandium", "Transition Metal", 44.956, [
            (424.68, 1.00, "Sc II Violet"), (402.37, 0.85, "Sc I Violet"),
            (508.16, 0.74, "Sc I Cyan"), (630.57, 0.60, "Sc I Orange")
        ]),
        (22, "Ti", "Titanium", "Transition Metal", 47.867, [
            (498.17, 1.00, "Ti I Cyan"), (453.32, 0.88, "Ti I Blue"),
            (399.86, 0.80, "Ti I Violet"), (521.04, 0.70, "Ti I Green")
        ]),
        (23, "V", "Vanadium", "Transition Metal", 50.942, [
            (437.92, 1.00, "V I Blue-Violet"), (411.18, 0.86, "V I Violet"),
            (488.16, 0.72, "V I Cyan"), (609.02, 0.58, "V I Orange")
        ]),
        (24, "Cr", "Chromium", "Transition Metal", 51.996, [
            (425.43, 1.00, "Cr I Violet"), (427.48, 0.92, "Cr I Indigo"),
            (520.84, 0.86, "Cr I Green"), (520.60, 0.78, "Cr I Emerald")
        ]),
        (25, "Mn", "Manganese", "Transition Metal", 54.938, [
            (403.08, 1.00, "Mn I Violet"), (403.31, 0.88, "Mn I Deep Violet"),
            (482.35, 0.76, "Mn I Blue"), (534.11, 0.62, "Mn I Green")
        ]),
        (26, "Fe", "Iron", "Transition Metal", 55.845, [
            (438.35, 1.00, "d Blue"), (404.58, 0.92, "Violet"), (495.76, 0.82, "Cyan"),
            (526.95, 0.78, "E2 Green"), (532.80, 0.75, "Green"), (619.16, 0.52, "Orange")
        ]),
        (27, "Co", "Cobalt", "Transition Metal", 58.933, [
            (412.13, 1.00, "Co I Violet"), (399.53, 0.86, "Co I Deep Violet"),
            (486.79, 0.74, "Co I Cyan"), (548.33, 0.60, "Co I Green")
        ]),
        (28, "Ni", "Nickel", "Transition Metal", 58.693, [
            (440.15, 0.94, "Ni I Blue"), (471.44, 0.86, "Ni I Cyan-Blue"),
            (547.69, 1.00, "Ni I Green"), (508.05, 0.72, "Ni I Emerald")
        ]),
        (29, "Cu", "Copper", "Transition Metal", 63.546, [
            (510.55, 1.00, "Emerald 1"), (521.82, 0.90, "Emerald 2"),
            (515.32, 0.82, "Green"), (578.21, 0.75, "Gold")
        ]),
        (30, "Zn", "Zinc", "Transition Metal", 65.38, [
            (481.05, 1.00, "Zn I Cyan-Blue"), (472.22, 0.88, "Zn I Blue"),
            (468.01, 0.72, "Zn I Deep Blue"), (636.23, 0.82, "Zn I Red-Orange")
        ]),
        (31, "Ga", "Gallium", "Post-Transition Metal", 69.723, [
            (417.20, 1.00, "Ga I Violet"), (403.30, 0.82, "Ga I Deep Violet"),
            (639.66, 0.55, "Ga I Red-Orange")
        ]),
        (32, "Ge", "Germanium", "Metalloid", 72.630, [
            (422.66, 0.94, "Ge I Violet"), (468.58, 0.82, "Ge I Blue"),
            (589.34, 0.76, "Ge II Gold"), (602.10, 0.68, "Ge II Orange")
        ]),
        (33, "As", "Arsenic", "Metalloid", 74.922, [
            (449.42, 0.88, "As II Blue"), (523.14, 0.82, "As II Green"),
            (555.81, 0.95, "As II Lime"), (617.03, 0.70, "As II Orange")
        ]),
        (34, "Se", "Selenium", "Nonmetal", 78.971, [
            (473.08, 0.92, "Se I Blue"), (522.75, 0.88, "Se II Green"),
            (530.54, 0.82, "Se II Emerald"), (644.42, 0.65, "Se II Red-Orange")
        ]),
        (35, "Br", "Bromine", "Halogen", 79.904, [
            (470.49, 1.00, "Br II Blue"), (478.55, 0.88, "Br II Cyan"),
            (533.20, 0.74, "Br II Green"), (614.86, 0.66, "Br I Orange")
        ]),
        (36, "Kr", "Krypton", "Noble Gas", 83.798, [
            (557.03, 1.00, "Green"), (587.09, 0.90, "Yellow"),
            (431.96, 0.65, "Violet"), (450.24, 0.60, "Blue")
        ])
    ]

    // MARK: - Period 5 (Z = 37...54)

    private static let period5: [ElementRow] = [
        (37, "Rb", "Rubidium", "Alkali Metal", 85.468, [
            (420.18, 1.00, "Rb I Violet"), (421.55, 0.82, "Rb I Indigo"),
            (629.83, 0.68, "Rb I Red-Orange"), (775.76, 0.78, "Rb I Deep Red")
        ]),
        (38, "Sr", "Strontium", "Alkaline Earth", 87.62, [
            (460.73, 0.95, "Blue"), (640.85, 0.85, "Red-Orange"),
            (707.01, 0.80, "Crimson"), (679.10, 0.70, "Red")
        ]),
        (39, "Y", "Yttrium", "Transition Metal", 88.906, [
            (410.24, 1.00, "Y I Violet"), (437.49, 0.92, "Y II Blue"),
            (488.37, 0.80, "Y II Cyan"), (619.17, 0.65, "Y I Orange")
        ]),
        (40, "Zr", "Zirconium", "Transition Metal", 91.224, [
            (468.78, 1.00, "Zr I Blue"), (414.92, 0.88, "Zr II Violet"),
            (471.01, 0.78, "Zr I Cyan-Blue"), (612.74, 0.62, "Zr I Orange")
        ]),
        (41, "Nb", "Niobium", "Transition Metal", 92.906, [
            (405.89, 1.00, "Nb I Violet"), (407.97, 0.88, "Nb I Indigo"),
            (467.21, 0.74, "Nb I Blue"), (534.42, 0.60, "Nb I Green")
        ]),
        (42, "Mo", "Molybdenum", "Transition Metal", 95.95, [
            (390.30, 1.00, "Mo I Violet"), (550.65, 0.94, "Mo I Green"),
            (553.30, 0.84, "Mo I Lime"), (603.06, 0.68, "Mo I Orange")
        ]),
        (43, "Tc", "Technetium", "Transition Metal", 98.0, [
            (429.71, 1.00, "Tc I Violet"), (426.23, 0.88, "Tc I Indigo"),
            (403.16, 0.76, "Tc I Deep Violet"), (485.36, 0.64, "Tc I Cyan")
        ]),
        (44, "Ru", "Ruthenium", "Transition Metal", 101.07, [
            (455.45, 1.00, "Ru I Blue"), (408.06, 0.86, "Ru I Violet"),
            (470.95, 0.74, "Ru I Cyan-Blue"), (569.90, 0.60, "Ru I Yellow-Green")
        ]),
        (45, "Rh", "Rhodium", "Transition Metal", 102.91, [
            (437.48, 1.00, "Rh I Blue"), (421.11, 0.86, "Rh I Violet"),
            (452.87, 0.74, "Rh I Azure"), (559.94, 0.58, "Rh I Green")
        ]),
        (46, "Pd", "Palladium", "Transition Metal", 106.42, [
            (421.29, 1.00, "Pd I Violet"), (447.36, 0.84, "Pd I Blue"),
            (516.38, 0.76, "Pd I Emerald"), (529.56, 0.68, "Pd I Green")
        ]),
        (47, "Ag", "Silver", "Transition Metal", 107.87, [
            (546.55, 1.00, "Ag I Green"), (520.91, 0.92, "Ag I Emerald"),
            (421.09, 0.72, "Ag I Violet"), (466.85, 0.64, "Ag I Blue")
        ]),
        (48, "Cd", "Cadmium", "Transition Metal", 112.41, [
            (508.58, 1.00, "Cd I Green"), (479.99, 0.92, "Cd I Blue"),
            (643.85, 0.96, "Cd I Standard Red"), (467.81, 0.76, "Cd I Deep Blue")
        ]),
        (49, "In", "Indium", "Post-Transition Metal", 114.82, [
            (451.13, 1.00, "In I Indigo-Blue"), (410.18, 0.88, "In I Violet"),
            (684.74, 0.52, "In I Red")
        ]),
        (50, "Sn", "Tin", "Post-Transition Metal", 118.71, [
            (452.47, 1.00, "Sn I Blue"), (563.17, 0.80, "Sn I Yellow-Green"),
            (645.35, 0.74, "Sn II Red-Orange"), (684.40, 0.62, "Sn II Red")
        ]),
        (51, "Sb", "Antimony", "Metalloid", 121.76, [
            (403.35, 0.92, "Sb I Violet"), (556.81, 0.96, "Sb II Green"),
            (600.50, 0.84, "Sb II Orange"), (612.99, 0.78, "Sb II Amber")
        ]),
        (52, "Te", "Tellurium", "Metalloid", 127.60, [
            (486.62, 0.94, "Te II Cyan"), (570.81, 0.96, "Te II Yellow-Green"),
            (597.47, 0.82, "Te II Orange"), (624.54, 0.68, "Te I Red-Orange")
        ]),
        (53, "I", "Iodine", "Halogen", 126.90, [
            (516.12, 1.00, "I II Green"), (546.46, 0.88, "I II Emerald"),
            (562.57, 0.80, "I II Yellow-Green"), (607.50, 0.66, "I II Orange")
        ]),
        (54, "Xe", "Xenon", "Noble Gas", 131.29, [
            (467.12, 1.00, "Xe I Blue"), (462.43, 0.92, "Xe I Azure"),
            (450.10, 0.80, "Xe I Deep Blue"), (484.43, 0.85, "Xe II Cyan"), (687.21, 0.64, "Xe I Red")
        ])
    ]

    // MARK: - Period 6 Main Group & Transition Metals (Z = 55...56, 72...86)

    private static let period6Main: [ElementRow] = [
        (55, "Cs", "Cesium", "Alkali Metal", 132.91, [
            (455.53, 1.00, "Cs I Sky Blue"), (459.32, 0.85, "Cs I Azure"),
            (672.33, 0.74, "Cs I Crimson"), (697.33, 0.66, "Cs I Deep Red")
        ]),
        (56, "Ba", "Barium", "Alkaline Earth", 137.327, [
            (553.55, 1.00, "Apple Green"), (493.41, 0.80, "Ba II Cyan"),
            (614.17, 0.70, "Orange"), (649.69, 0.60, "Red")
        ]),
        (72, "Hf", "Hafnium", "Transition Metal", 178.49, [
            (409.32, 1.00, "Hf II Violet"), (417.43, 0.86, "Hf I Indigo"),
            (462.09, 0.72, "Hf I Blue"), (531.16, 0.60, "Hf I Green")
        ]),
        (73, "Ta", "Tantalum", "Transition Metal", 180.95, [
            (481.28, 0.94, "Ta I Blue"), (540.25, 1.00, "Ta I Green"),
            (457.43, 0.80, "Ta I Azure"), (648.54, 0.62, "Ta I Red")
        ]),
        (74, "W", "Tungsten", "Transition Metal", 183.84, [
            (400.88, 1.00, "W I Violet"), (429.46, 0.90, "W I Indigo"),
            (484.38, 0.78, "W I Cyan"), (505.33, 0.70, "W I Green")
        ]),
        (75, "Re", "Rhenium", "Transition Metal", 186.21, [
            (488.91, 1.00, "Re I Cyan"), (527.55, 0.90, "Re I Green"),
            (451.33, 0.76, "Re I Blue"), (635.07, 0.62, "Re I Red-Orange")
        ]),
        (76, "Os", "Osmium", "Transition Metal", 190.23, [
            (442.05, 1.00, "Os I Blue"), (426.08, 0.90, "Os I Violet"),
            (479.40, 0.74, "Os I Cyan-Blue"), (552.35, 0.60, "Os I Green")
        ]),
        (77, "Ir", "Iridium", "Transition Metal", 192.22, [
            (402.00, 0.92, "Ir I Violet"), (439.95, 1.00, "Ir I Blue"),
            (544.95, 0.82, "Ir I Green"), (611.07, 0.64, "Ir I Orange")
        ]),
        (78, "Pt", "Platinum", "Transition Metal", 195.08, [
            (444.26, 0.94, "Pt I Blue"), (530.10, 1.00, "Pt I Green"),
            (547.58, 0.86, "Pt I Emerald"), (411.87, 0.72, "Pt I Violet")
        ]),
        (79, "Au", "Gold", "Transition Metal", 196.97, [
            (479.26, 0.86, "Au I Blue"), (583.74, 1.00, "Au I Gold"),
            (627.82, 0.92, "Au I Warm Orange"), (523.03, 0.68, "Au I Green")
        ]),
        (80, "Hg", "Mercury", "Transition Metal", 200.592, [
            (546.07, 1.00, "e Green"), (435.83, 0.92, "g Blue-Violet"),
            (576.96, 0.78, "Yellow 1"), (579.07, 0.76, "Yellow 2"), (404.66, 0.68, "h Violet")
        ]),
        (81, "Tl", "Thallium", "Post-Transition Metal", 204.38, [
            (535.05, 1.00, "Tl I Vivid Green"), (654.98, 0.56, "Tl I Red"),
            (473.71, 0.48, "Tl II Blue")
        ]),
        (82, "Pb", "Lead", "Post-Transition Metal", 207.2, [
            (405.78, 1.00, "Pb I Violet"), (500.54, 0.74, "Pb I Cyan"),
            (560.89, 0.80, "Pb II Yellow-Green"), (666.02, 0.68, "Pb II Red")
        ]),
        (83, "Bi", "Bismuth", "Post-Transition Metal", 208.98, [
            (472.25, 1.00, "Bi I Blue"), (412.19, 0.82, "Bi I Violet"),
            (520.92, 0.76, "Bi II Green"), (613.48, 0.64, "Bi I Orange")
        ]),
        (84, "Po", "Polonium", "Post-Transition Metal", 209.0, [
            (417.05, 1.00, "Po I Violet"), (449.32, 0.84, "Po I Blue"),
            (594.06, 0.72, "Po I Amber")
        ]),
        (85, "At", "Astatine", "Halogen", 210.0, [
            (456.40, 0.90, "At I Blue"), (528.20, 0.85, "At I Green"),
            (632.50, 0.75, "At I Red-Orange")
        ]),
        (86, "Rn", "Radon", "Noble Gas", 222.0, [
            (745.00, 1.00, "Rn I Far Red"), (705.54, 0.92, "Rn I Crimson"),
            (434.96, 0.84, "Rn I Blue-Violet"), (558.23, 0.72, "Rn I Green")
        ])
    ]

    // MARK: - Lanthanides (Z = 57...71)

    private static let lanthanides: [ElementRow] = [
        (57, "La", "Lanthanum", "Lanthanide", 138.91, [
            (408.67, 1.00, "La II Violet"), (433.37, 0.88, "La II Blue-Violet"),
            (550.13, 0.76, "La I Green"), (624.99, 0.68, "La I Orange")
        ]),
        (58, "Ce", "Cerium", "Lanthanide", 140.12, [
            (418.66, 1.00, "Ce II Violet"), (456.24, 0.88, "Ce II Blue"),
            (527.42, 0.76, "Ce II Green"), (569.92, 0.64, "Ce I Yellow-Green")
        ]),
        (59, "Pr", "Praseodymium", "Lanthanide", 140.91, [
            (417.94, 1.00, "Pr II Violet"), (422.53, 0.90, "Pr II Indigo"),
            (495.14, 0.80, "Pr I Cyan"), (522.01, 0.72, "Pr II Green")
        ]),
        (60, "Nd", "Neodymium", "Lanthanide", 144.24, [
            (430.36, 1.00, "Nd II Violet-Blue"), (401.22, 0.92, "Nd II Violet"),
            (492.45, 0.80, "Nd I Cyan"), (562.05, 0.68, "Nd I Yellow-Green")
        ]),
        (61, "Pm", "Promethium", "Lanthanide", 145.0, [
            (441.79, 1.00, "Pm II Blue"), (495.95, 0.86, "Pm I Cyan"),
            (554.61, 0.74, "Pm II Green"), (652.04, 0.64, "Pm I Red")
        ]),
        (62, "Sm", "Samarium", "Lanthanide", 150.36, [
            (442.43, 1.00, "Sm II Blue"), (429.67, 0.88, "Sm I Violet"),
            (476.03, 0.78, "Sm I Azure"), (658.97, 0.66, "Sm I Red")
        ]),
        (63, "Eu", "Europium", "Lanthanide", 151.96, [
            (420.50, 1.00, "Eu II Violet"), (459.40, 0.96, "Eu I Blue"),
            (462.72, 0.88, "Eu I Azure"), (664.51, 0.84, "Eu II Phosphor Red")
        ]),
        (64, "Gd", "Gadolinium", "Lanthanide", 157.25, [
            (422.58, 1.00, "Gd I Violet"), (409.86, 0.88, "Gd II Deep Violet"),
            (501.50, 0.76, "Gd I Cyan-Green"), (561.79, 0.66, "Gd I Yellow-Green")
        ]),
        (65, "Tb", "Terbium", "Lanthanide", 158.93, [
            (432.65, 0.96, "Tb I Blue-Violet"), (542.85, 1.00, "Tb Phosphor Green"),
            (487.55, 0.80, "Tb I Cyan"), (584.72, 0.66, "Tb I Gold")
        ]),
        (66, "Dy", "Dysprosium", "Lanthanide", 162.50, [
            (421.17, 1.00, "Dy I Violet"), (404.60, 0.92, "Dy I Deep Violet"),
            (458.94, 0.80, "Dy I Blue"), (598.86, 0.68, "Dy I Orange")
        ]),
        (67, "Ho", "Holmium", "Lanthanide", 164.93, [
            (410.38, 1.00, "Ho I Violet"), (416.30, 0.88, "Ho I Indigo"),
            (598.29, 0.76, "Ho I Orange"), (660.49, 0.64, "Ho I Red")
        ]),
        (68, "Er", "Erbium", "Lanthanide", 167.26, [
            (400.80, 1.00, "Er I Violet"), (415.11, 0.88, "Er I Indigo"),
            (582.68, 0.76, "Er I Gold"), (622.10, 0.66, "Er I Orange")
        ]),
        (69, "Tm", "Thulium", "Lanthanide", 168.93, [
            (410.58, 1.00, "Tm I Violet"), (409.42, 0.90, "Tm I Deep Violet"),
            (473.33, 0.76, "Tm I Blue"), (563.14, 0.66, "Tm I Green")
        ]),
        (70, "Yb", "Ytterbium", "Lanthanide", 173.05, [
            (398.80, 1.00, "Yb I Violet"), (555.65, 0.92, "Yb I Green"),
            (648.91, 0.76, "Yb I Red"), (493.55, 0.66, "Yb I Cyan")
        ]),
        (71, "Lu", "Lutetium", "Lanthanide", 174.97, [
            (451.86, 1.00, "Lu I Blue"), (547.67, 0.88, "Lu II Green"),
            (622.19, 0.80, "Lu II Orange"), (499.41, 0.68, "Lu I Cyan")
        ])
    ]

    // MARK: - Period 7 Main Group & Transactinides (Z = 87...88, 104...118)

    private static let period7Main: [ElementRow] = [
        (87, "Fr", "Francium", "Alkali Metal", 223.0, [
            (717.97, 1.00, "Fr I D2 Crimson"), (422.57, 0.80, "Fr I Violet"),
            (432.54, 0.68, "Fr I Blue-Violet")
        ]),
        (88, "Ra", "Radium", "Alkaline Earth", 226.0, [
            (482.59, 1.00, "Ra I Blue"), (468.22, 0.92, "Ra II Azure"),
            (644.62, 0.78, "Ra I Red-Orange"), (714.12, 0.72, "Ra I Crimson")
        ]),
        (104, "Rf", "Rutherfordium", "Transition Metal", 267.0, [
            (418.00, 0.95, "Theoretical Relativistic"), (492.00, 0.82, "Theoretical Relativistic"),
            (584.00, 0.70, "Theoretical Relativistic")
        ]),
        (105, "Db", "Dubnium", "Transition Metal", 268.0, [
            (432.00, 0.95, "Theoretical Relativistic"), (516.00, 0.80, "Theoretical Relativistic"),
            (612.00, 0.68, "Theoretical Relativistic")
        ]),
        (106, "Sg", "Seaborgium", "Transition Metal", 269.0, [
            (446.00, 0.96, "Theoretical Relativistic"), (528.00, 0.82, "Theoretical Relativistic"),
            (626.00, 0.70, "Theoretical Relativistic")
        ]),
        (107, "Bh", "Bohrium", "Transition Metal", 270.0, [
            (462.00, 0.94, "Theoretical Relativistic"), (544.00, 0.84, "Theoretical Relativistic"),
            (638.00, 0.72, "Theoretical Relativistic")
        ]),
        (108, "Hs", "Hassium", "Transition Metal", 277.0, [
            (474.00, 0.96, "Theoretical Relativistic"), (558.00, 0.82, "Theoretical Relativistic"),
            (646.00, 0.68, "Theoretical Relativistic")
        ]),
        (109, "Mt", "Meitnerium", "Transition Metal", 278.0, [
            (486.00, 0.94, "Theoretical Relativistic"), (566.00, 0.80, "Theoretical Relativistic"),
            (658.00, 0.72, "Theoretical Relativistic")
        ]),
        (110, "Ds", "Darmstadtium", "Transition Metal", 281.0, [
            (498.00, 0.95, "Theoretical Relativistic"), (578.00, 0.84, "Theoretical Relativistic"),
            (668.00, 0.70, "Theoretical Relativistic")
        ]),
        (111, "Rg", "Roentgenium", "Transition Metal", 282.0, [
            (514.00, 0.96, "Theoretical Relativistic"), (596.00, 0.86, "Theoretical Relativistic"),
            (676.00, 0.72, "Theoretical Relativistic")
        ]),
        (112, "Cn", "Copernicium", "Transition Metal", 285.0, [
            (526.00, 0.94, "Theoretical Relativistic"), (606.00, 0.82, "Theoretical Relativistic"),
            (442.00, 0.74, "Theoretical Relativistic")
        ]),
        (113, "Nh", "Nihonium", "Post-Transition Metal", 286.0, [
            (542.00, 0.96, "Theoretical Relativistic"), (466.00, 0.84, "Theoretical Relativistic"),
            (634.00, 0.70, "Theoretical Relativistic")
        ]),
        (114, "Fl", "Flerovium", "Post-Transition Metal", 289.0, [
            (454.00, 0.95, "Theoretical Relativistic"), (562.00, 0.82, "Theoretical Relativistic"),
            (648.00, 0.72, "Theoretical Relativistic")
        ]),
        (115, "Mc", "Moscovium", "Post-Transition Metal", 290.0, [
            (478.00, 0.96, "Theoretical Relativistic"), (586.00, 0.84, "Theoretical Relativistic"),
            (664.00, 0.72, "Theoretical Relativistic")
        ]),
        (116, "Lv", "Livermorium", "Post-Transition Metal", 293.0, [
            (494.00, 0.95, "Theoretical Relativistic"), (604.00, 0.84, "Theoretical Relativistic"),
            (682.00, 0.74, "Theoretical Relativistic")
        ]),
        (117, "Ts", "Tennessine", "Halogen", 294.0, [
            (512.00, 0.96, "Theoretical Relativistic"), (618.00, 0.86, "Theoretical Relativistic"),
            (694.00, 0.72, "Theoretical Relativistic")
        ]),
        (118, "Og", "Oganesson", "Noble Gas", 294.0, [
            (448.00, 0.98, "Theoretical Relativistic"), (572.00, 0.86, "Theoretical Relativistic"),
            (688.00, 0.78, "Theoretical Relativistic")
        ])
    ]

    // MARK: - Actinides (Z = 89...103)

    private static let actinides: [ElementRow] = [
        (89, "Ac", "Actinium", "Actinide", 227.0, [
            (417.99, 1.00, "Ac I Violet"), (408.84, 0.90, "Ac II Deep Violet"),
            (450.72, 0.78, "Ac II Blue"), (591.09, 0.66, "Ac II Gold")
        ]),
        (90, "Th", "Thorium", "Actinide", 232.04, [
            (401.91, 1.00, "Th II Violet"), (438.19, 0.88, "Th II Blue"),
            (491.98, 0.78, "Th II Cyan"), (576.06, 0.68, "Th I Yellow")
        ]),
        (91, "Pa", "Protactinium", "Actinide", 231.04, [
            (398.22, 1.00, "Pa I Violet"), (421.72, 0.88, "Pa II Indigo"),
            (510.14, 0.74, "Pa I Emerald"), (637.92, 0.64, "Pa I Red-Orange")
        ]),
        (92, "U", "Uranium", "Actinide", 238.0289, [
            (424.17, 0.95, "U II Violet"), (591.54, 0.90, "U I Yellow"),
            (502.74, 0.75, "Cyan-Green"), (549.29, 0.70, "Green"), (644.92, 0.65, "Red")
        ]),
        (93, "Np", "Neptunium", "Actinide", 237.0, [
            (429.09, 1.00, "Np II Violet-Blue"), (456.04, 0.86, "Np II Blue"),
            (504.47, 0.76, "Np I Cyan"), (615.20, 0.66, "Np I Orange")
        ]),
        (94, "Pu", "Plutonium", "Actinide", 244.0, [
            (453.61, 1.00, "Pu II Blue"), (420.64, 0.88, "Pu I Violet"),
            (504.45, 0.78, "Pu I Cyan"), (586.48, 0.70, "Pu I Gold")
        ]),
        (95, "Am", "Americium", "Actinide", 243.0, [
            (408.93, 1.00, "Am II Violet"), (457.56, 0.90, "Am II Blue"),
            (503.61, 0.80, "Am I Cyan"), (605.46, 0.70, "Am I Orange")
        ]),
        (96, "Cm", "Curium", "Actinide", 247.0, [
            (420.77, 1.00, "Cm I Violet"), (434.03, 0.88, "Cm I Blue-Violet"),
            (512.34, 0.76, "Cm I Emerald"), (597.80, 0.66, "Cm I Orange")
        ]),
        (97, "Bk", "Berkelium", "Actinide", 247.0, [
            (413.21, 1.00, "Bk I Violet"), (470.52, 0.86, "Bk I Blue"),
            (536.14, 0.74, "Bk I Green"), (621.80, 0.64, "Bk I Orange")
        ]),
        (98, "Cf", "Californium", "Actinide", 251.0, [
            (430.86, 1.00, "Cf I Violet-Blue"), (480.42, 0.86, "Cf I Cyan-Blue"),
            (544.20, 0.76, "Cf I Green"), (611.65, 0.66, "Cf I Orange")
        ]),
        (99, "Es", "Einsteinium", "Actinide", 252.0, [
            (421.84, 1.00, "Es I Violet"), (516.17, 0.88, "Es I Emerald"),
            (567.85, 0.78, "Es I Yellow-Green"), (634.10, 0.66, "Es I Red-Orange")
        ]),
        (100, "Fm", "Fermium", "Actinide", 257.0, [
            (436.40, 0.96, "Theoretical Relativistic"), (524.80, 0.84, "Theoretical Relativistic"),
            (614.20, 0.72, "Theoretical Relativistic")
        ]),
        (101, "Md", "Mendelevium", "Actinide", 258.0, [
            (448.60, 0.95, "Theoretical Relativistic"), (538.40, 0.82, "Theoretical Relativistic"),
            (628.50, 0.70, "Theoretical Relativistic")
        ]),
        (102, "No", "Nobelium", "Actinide", 259.0, [
            (461.20, 0.96, "Theoretical Relativistic"), (552.10, 0.84, "Theoretical Relativistic"),
            (642.00, 0.72, "Theoretical Relativistic")
        ]),
        (103, "Lr", "Lawrencium", "Actinide", 266.0, [
            (472.50, 0.96, "Theoretical Relativistic"), (564.80, 0.85, "Theoretical Relativistic"),
            (654.40, 0.72, "Theoretical Relativistic")
        ])
    ]
}
