import Foundation

enum DomainGroup: String, CaseIterable {
    case general, professional
}

enum DomainCategory: String {
    case none
    case humanities   // 人文社科
    case bizMed       // 商業醫學
    case infoEng      // 資訊工程
    case science      // 自然科學
    case geoMil       // 地理軍事
}

struct DomainEntry: Identifiable, Hashable {
    let id: String
    let file: String
    let label: String
    let icon: String
    let desc: String
    let group: DomainGroup
    var category: DomainCategory = .none
}

enum DomainData {
    static let generalDomains: [DomainEntry] = [
        .init(id: "domain_ner", file: "ner_phrases", label: "NER 詞組", icon: "person.text.rectangle", desc: "人名地名機構", group: .general),
        .init(id: "domain_phrases", file: "phrases", label: "萌典詞組", icon: "character.book.closed", desc: "教育部辭典", group: .general),
        .init(id: "domain_chengyu", file: "chengyu", label: "成語", icon: "text.quote", desc: "四字成語典故", group: .general),
        .init(id: "domain_jingjing", file: "terms_jingjing", label: "晶晶體", icon: "globe.americas", desc: "台式中英夾雜", group: .general),
        .init(id: "domain_cn_slang", file: "terms_cn_slang", label: "中國流行語", icon: "bubble.left", desc: "中式網路用語", group: .general),
        .init(id: "domain_xiehouyu", file: "terms_xiehouyu", label: "歇後語", icon: "theatermasks", desc: "中華新華字典", group: .general),
        .init(id: "domain_kautian", file: "terms_kautian", label: "台灣俗諺", icon: "quote.bubble", desc: "教育部閩南語辭典", group: .general),
        .init(id: "domain_hakka", file: "terms_hakka", label: "客語辭典", icon: "person.2", desc: "教育部六腔客語", group: .general),
        .init(id: "domain_placename", file: "terms_placename", label: "台灣地名", icon: "mappin.and.ellipse", desc: "台鐵/捷運站名", group: .general),
        .init(id: "domain_ttg", file: "terms_ttg", label: "台語學科", icon: "graduationcap", desc: "教育部台語學科", group: .general),
        .init(id: "domain_korean", file: "terms_korean", label: "韓語漢字詞", icon: "k.circle", desc: "Kengdic 漢字詞", group: .general),
        .init(id: "domain_yoji", file: "yoji", label: "日本熟語", icon: "leaf", desc: "日式四字詞", group: .general),
    ]

    static let proDomains: [DomainEntry] = [
        // 商業醫學
        .init(id: "domain_biz", file: "terms_biz", label: "商業", icon: "chart.line.uptrend.xyaxis", desc: "金融會計管理", group: .professional, category: .bizMed),
        .init(id: "domain_med", file: "terms_med", label: "醫學", icon: "cross.case", desc: "臨床藥理病理", group: .professional, category: .bizMed),
        // 人文社科
        .init(id: "domain_law", file: "terms_law", label: "法律", icon: "building.columns", desc: "法規判例條文", group: .professional, category: .humanities),
        .init(id: "domain_edu", file: "terms_edu", label: "教育", icon: "graduationcap", desc: "教學課綱體育", group: .professional, category: .humanities),
        .init(id: "domain_media", file: "terms_media", label: "傳播", icon: "newspaper", desc: "新聞媒體出版", group: .professional, category: .humanities),
        .init(id: "domain_social", file: "terms_social", label: "社會", icon: "person.3", desc: "社工行政福利", group: .professional, category: .humanities),
        .init(id: "domain_govt", file: "terms_govt", label: "政府", icon: "building.2", desc: "機關職稱公文", group: .professional, category: .humanities),
        .init(id: "domain_art", file: "terms_art", label: "藝術", icon: "paintpalette", desc: "視覺音樂舞蹈", group: .professional, category: .humanities),
        // 資訊工程
        .init(id: "domain_it", file: "terms_it", label: "資訊", icon: "desktopcomputer", desc: "軟體硬體網路", group: .professional, category: .infoEng),
        .init(id: "domain_ee", file: "terms_ee", label: "電機", icon: "bolt", desc: "電機電子通訊", group: .professional, category: .infoEng),
        .init(id: "domain_power", file: "terms_power", label: "電力", icon: "bolt.batteryblock", desc: "電力電工能源", group: .professional, category: .infoEng),
        .init(id: "domain_eng", file: "terms_eng", label: "土木水利", icon: "wrench.and.screwdriver", desc: "土木水利工業", group: .professional, category: .infoEng),
        .init(id: "domain_aero", file: "terms_aero", label: "航太", icon: "airplane", desc: "航空太空", group: .professional, category: .infoEng),
        .init(id: "domain_nuclear", file: "terms_nuclear", label: "核能", icon: "bolt.trianglebadge.exclamationmark", desc: "核能工程", group: .professional, category: .infoEng),
        .init(id: "domain_textile", file: "terms_textile", label: "輕工業", icon: "tshirt", desc: "紡織食品輕工", group: .professional, category: .infoEng),
        .init(id: "domain_mech", file: "terms_mech", label: "機械", icon: "gearshape.2", desc: "機械工程製造", group: .professional, category: .infoEng),
        // 自然科學
        .init(id: "domain_math", file: "terms_math", label: "數學", icon: "function", desc: "代數幾何統計", group: .professional, category: .science),
        .init(id: "domain_phy", file: "terms_phy", label: "物理", icon: "atom", desc: "力學光學計量", group: .professional, category: .science),
        .init(id: "domain_chem", file: "terms_chem", label: "化學", icon: "flask", desc: "有機無機化工", group: .professional, category: .science),
        .init(id: "domain_bio", file: "terms_bio", label: "動物生態", icon: "leaf.arrow.circlepath", desc: "動物生態學", group: .professional, category: .science),
        .init(id: "domain_botany", file: "terms_botany", label: "植物", icon: "leaf", desc: "植物學物種", group: .professional, category: .science),
        .init(id: "domain_fish", file: "terms_fish", label: "魚類", icon: "fish", desc: "魚類水產", group: .professional, category: .science),
        .init(id: "domain_material", file: "terms_material", label: "材料", icon: "cube", desc: "材料礦物冶金", group: .professional, category: .science),
        .init(id: "domain_agri", file: "terms_agri", label: "農林", icon: "tree", desc: "農林畜牧漁業", group: .professional, category: .science),
        // 地理軍事
        .init(id: "domain_geo", file: "terms_geo", label: "地理", icon: "globe.asia.australia", desc: "地質氣象測繪", group: .professional, category: .geoMil),
        .init(id: "domain_placename_intl", file: "terms_placename_intl", label: "外國地名", icon: "globe.europe.africa", desc: "國教院譯名", group: .professional, category: .geoMil),
        .init(id: "domain_marine", file: "terms_marine", label: "海事", icon: "ferry", desc: "航海造船輪機", group: .professional, category: .geoMil),
        .init(id: "domain_mil", file: "terms_mil", label: "軍事", icon: "shield.checkered", desc: "國防軍語武器", group: .professional, category: .geoMil),
    ]

    static let allDomains: [DomainEntry] = generalDomains + proDomains

    static let proCategoryOrder: [DomainCategory] = [.bizMed, .humanities, .infoEng, .science, .geoMil]

    static func categoryLabel(_ cat: DomainCategory) -> String {
        switch cat {
        case .bizMed:     return "商業醫學"
        case .humanities: return "人文社科"
        case .infoEng:    return "資訊工程"
        case .science:    return "自然科學"
        case .geoMil:     return "地理軍事"
        case .none:       return ""
        }
    }

    static func binEntryCount(file: String) -> Int {
        let paths = [
            "/Library/Input Methods/YabomishIM.app/Contents/Resources/\(file).bin",
            NSHomeDirectory() + "/Library/YabomishIM/\(file).bin",
            Bundle.main.path(forResource: file, ofType: "bin")
        ].compactMap { $0 }
        guard let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let fh = FileHandle(forReadingAtPath: path) else { return 0 }
        defer { try? fh.close() }
        let header = fh.readData(ofLength: 8)
        guard header.count >= 8,
              header[0] == 0x57, header[1] == 0x42, header[2] == 0x4D, header[3] == 0x4D else { return 0 }
        return Int(header[4]) | Int(header[5]) << 8 | Int(header[6]) << 16 | Int(header[7]) << 24
    }
}
