import Foundation

/// Mots mis en évidence (gras + orange) dans les textes d'activité et d'historique (demandes d'Yves du 07/11/2026) :
/// - « signer » et toutes ses formes (resigner, re-signature, contresigné, cosigner, e-signature, signataire…) ;
/// - « devis », « contrat » et voisins (contractuel, avenant, bon de commande, propale, proposition commerciale) ;
/// - « accès » (accès, acces, accés, accéder…) ;
/// - les mots du métier qui suivent l'un de ces mots : « devis audit sécu », « devis SEO et SEA »,
///   « signature GEO », « accès au compte Google Ads », « devis d'audit SEO »…
public enum KeywordHighlight {
    /// Mots déclencheurs.
    static let keywords: [String] = [
        // signer : préfixes re / ré / contre / co / e, conjugaisons, signature, signataire
        #"(?:re-?|ré-?|contre-?|co-?|e-|é-)?sign(?:er|e|es|ent|ez|ons|é|ée|és|ées|ai|ais|ait|aient|ant|iez|ions|a|as|âmes|âtes|èrent|era|erai|eras|erons|erez|eront|erait|erais|eraient|erions|eriez|ature|atures|ataire|ataires)"#,
        #"devis"#,
        #"contrats?"#,
        #"contractuel(?:le)?s?"#,
        #"contractualis(?:er|e|é|ée|és|ées|ation|ations)"#,
        #"avenants?"#,
        #"bons?[ \t\u00A0]+de[ \t\u00A0]+commande"#,
        #"propales?"#,
        #"propositions?[ \t\u00A0]+commerciales?"#,
        #"acc[eèé]s"#,
        #"acc[eéè]d(?:er|e|es|ent|ons|ez|é|ée|és|ées)"#,
    ]

    /// Mots du métier mis en évidence quand ils suivent un mot déclencheur (expressions de plusieurs mots d'abord).
    static let trades: [String] = [
        #"google[ \t\u00A0]+(?:ads|analytics|tag[ \t\u00A0]+manager|search[ \t\u00A0]+console|merchant[ \t\u00A0]+center|my[ \t\u00A0]+business)"#,
        #"(?:meta|facebook|fb|g|instagram|linkedin|tiktok|microsoft|bing|amazon|social|youtube|pinterest|snapchat)[ \t\u00A0]+ads"#,
        #"mont[ée]es?[ \t\u00A0]+(?:de[ \t\u00A0]+)?versions?"#,
        #"mises?[ \t\u00A0]+[àa][ \t\u00A0]+jour"#,
        #"server[ \t\u00A0-]+side|hors[ \t\u00A0]+ligne|one[ \t\u00A0-]+shot|back[ \t\u00A0-]?office"#,
        #"tag[ \t\u00A0]+manager"#,
        #"search[ \t\u00A0]+console"#,
        #"merchant[ \t\u00A0]+center"#,
        #"performance[ \t\u00A0]+max"#,
        #"looker[ \t\u00A0]+studio"#,
        #"r[ée]seaux[ \t\u00A0]+sociaux"#,
        #"community[ \t\u00A0]+management"#,
        #"landing[ \t\u00A0]+pages?"#,
        #"sites?[ \t\u00A0]+(?:web|internet|vitrine|e-?commerce)"#,
        #"seo|sea|geo|sma|smo|sxo|aeo|sem|paid|cro|tma|amoa"#,
        #"ads|gads|adwords|google|meta|facebook|fb|instagram|linkedin|tiktok|bing|microsoft|amazon|youtube|pinterest|snapchat"#,
        #"pmax|shopping|merchant|gsc|ga4|ga|gtm|gmb|analytics|looker|matomo|tracking|attribution|ss"#,
        #"audits?|diag(?:nostic)?s?|s[ée]cu(?:rit[ée])?|technique|perf|performances?|speed|fixe|local|international"#,
        #"sites?|web|refonte|versions?|migrations?|cr[ée]ation|conception|maintenance|h[ée]bergement|ftp|bo|cloudflare|bazaarvoice"#,
        // Abréviations d'Yves : MEV = montée de version, MAJ = mise à jour, PS = PrestaShop (demande du 11/11/2026).
        #"mev|maj|ps|vitesse|klaviyo"#,
        #"netlinking|bl|backlinks?|contenus?|r[ée]daction|acquis|acquisition|campagnes?|strat[ée]gie|accompagnement|formation"#,
        #"dev|d[ée]veloppements?|[ée]volutions?|[ée]volutive|tickets?|plateforme|marketplace|b2b|b2c"#,
        #"ux|ui|e-?commerce|applications?|app|appli|wordpress|shopify|prestashop|webflow|magento|woocommerce|drupal"#,
        #"emailing|newsletters?|display|vid[ée]os?|rgpd|comptes?"#,
        #"bugs?|beugs?|bogues?|debug|correctifs?|corrections?|anomalies?|hotfix|fix|recette|support|incidents?|urgences?"#,
        #"modifs?|modifications?|int[ée]grations?|modules?|plugins?|th[èe]mes?|maquettes?|design|graphisme|charte|logo"#,
        #"ssl|domaines?|serveurs?|infog[ée]rance|api|flux|catalogues?|traductions?|multilingue|automatisations?|crm|cms|pim|erp"#,
        #"recos|recommandations?|conseil|optimisations?|sauvegardes?|monitoring|pentest|cookies|consentement|cmp|avis"#,
    ]

    /// Petits mots autorisés entre deux mots mis en évidence (« devis d'audit », « accès au compte », « SEO et SEA »,
    /// « refonte ou montée de version », « SEO à la perf »).
    static let connectors = #"(?:(?:de|du|des|pour|le|la|les|en|et|ou|au|aux|à|a)[ \t\u00A0]+|[dl]['’])"#

    /// Séparateur sur la même ligne : espaces, ou « / », « + », « & » (« GA4 / GTM », « SEO+SEA »).
    static let separator = #"(?:[ \t\u00A0]*[/+&][ \t\u00A0]*|[ \t\u00A0]+)"#

    static let pattern: String = {
        let keyword = "(?:" + keywords.joined(separator: "|") + ")"
        let trade = "(?:" + trades.joined(separator: "|") + ")"
        return #"\b"# + keyword + #"\b"# + "(?:" + separator + connectors + "*" + trade + #"\b)*"#
    }()

    static let regex: NSRegularExpression? = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])

    /// Plages des mots à mettre en évidence.
    public static func ranges(in text: String) -> [Range<String.Index>] {
        guard let regex else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { Range($0.range, in: text) }
    }
}
