import Foundation

enum DomainGroup: String, CaseIterable {
    case general, professional
}

struct DomainEntry: Identifiable, Hashable {
    let id: String   // key
    let file: String
    let label: String
    let group: DomainGroup
}

enum DomainData {
    static let generalDomains: [DomainEntry] = [
        .init(id: "domain_ner", file: "ner_phrases", label: "NER 詞組", group: .general),
        .init(id: "domain_phrases", file: "phrases", label: "萌典詞組", group: .general),
        .init(id: "domain_chengyu", file: "chengyu", label: "成語", group: .general),
        .init(id: "domain_yoji", file: "yoji", label: "日式四字熟語", group: .general),
        .init(id: "domain_cn_slang", file: "terms_cn_slang", label: "中式流行語", group: .general),
    ]

    static let proDomains: [DomainEntry] = [
        .init(id: "domain_it", file: "terms_it", label: "資訊科技", group: .professional),
        .init(id: "domain_ee", file: "terms_ee", label: "電機電子", group: .professional),
        .init(id: "domain_med", file: "terms_med", label: "醫學", group: .professional),
        .init(id: "domain_law", file: "terms_law", label: "法律", group: .professional),
        .init(id: "domain_phy", file: "terms_phy", label: "物理∕計量", group: .professional),
        .init(id: "domain_chem", file: "terms_chem", label: "化學", group: .professional),
        .init(id: "domain_bio", file: "terms_bio", label: "生物", group: .professional),
        .init(id: "domain_math", file: "terms_math", label: "數學", group: .professional),
        .init(id: "domain_biz", file: "terms_biz", label: "商業金融", group: .professional),
        .init(id: "domain_edu", file: "terms_edu", label: "教育", group: .professional),
        .init(id: "domain_geo", file: "terms_geo", label: "地理", group: .professional),
        .init(id: "domain_eng", file: "terms_eng", label: "工程", group: .professional),
        .init(id: "domain_art", file: "terms_art", label: "藝術", group: .professional),
        .init(id: "domain_mil", file: "terms_mil", label: "軍事", group: .professional),
        .init(id: "domain_marine", file: "terms_marine", label: "海事", group: .professional),
        .init(id: "domain_material", file: "terms_material", label: "材料∕礦物", group: .professional),
        .init(id: "domain_agri", file: "terms_agri", label: "農林畜牧", group: .professional),
        .init(id: "domain_media", file: "terms_media", label: "新聞傳播", group: .professional),
        .init(id: "domain_social", file: "terms_social", label: "社會行政", group: .professional),
        .init(id: "domain_govt", file: "terms_govt", label: "政府機關", group: .professional),
    ]

    static let allDomains: [DomainEntry] = generalDomains + proDomains
}
