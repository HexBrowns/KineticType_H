//! KineticType_H（v0.3.x までの名前は FlowType_H）— FlowType_K（Korarei、MIT）の C++ プラグインの Rust フォーク。
//!
//! 原作のソースは `plugins/`（C++、vcpkg が要る）に残してあり、ビルドしない。中身は次の 3 つで、すべて移植した。
//!
//! - フィルタ効果 4 つ（filters/）。効果名は日本語にした（トリミング / 変形 / 整列 / トランスフォーム）
//! - スクリプトモジュール 7 つ（modules/）。名前は `UTF8@KineticType_H` など（スクリプトがこの名前で読む。astra.toml の MODULE と揃える）
//! - メニュー（menus/）。オブジェクトのメニュー 1 つと、設定項目のメニュー 13 個
//!
//! 原作は行ごとの処理を並列にしていた（std::execution::par）。こちらはスレッドを起こさない
//! （プラグインが起こしたスレッドは外れる前に止める必要がある。ルール au2-rs-plugin）。

pub mod alias;
pub mod filters;
pub mod font;
pub mod math;
pub mod menus;
pub mod modules;
pub mod rotation;
pub mod smp;
pub mod utf8;

use aviutl2::generic::{GlobalEditHandle, SubPlugin};
use aviutl2::AnyResult;

pub static EDIT_HANDLE: GlobalEditHandle = GlobalEditHandle::new();

#[aviutl2::plugin(GenericPlugin)]
pub struct KineticTypeH {
    trim: SubPlugin<filters::trim::Trim>,
    deform: SubPlugin<filters::deform::Deform>,
    align: SubPlugin<filters::align::Align>,
    transform: SubPlugin<filters::transform::Transform>,
    utf8: SubPlugin<modules::utf8::Utf8Module>,
    regex: SubPlugin<modules::regex::RegexModule>,
    kerning: SubPlugin<modules::kerning::KerningModule>,
    hash: SubPlugin<modules::hash::HashModule>,
    toml: SubPlugin<modules::toml::TomlModule>,
    vector: SubPlugin<modules::vector::VectorModule>,
    island: SubPlugin<modules::island::IslandModule>,
}

impl aviutl2::generic::GenericPlugin for KineticTypeH {
    fn new(info: aviutl2::AviUtl2Info) -> AnyResult<Self> {
        aviutl2::tracing_subscriber::fmt()
            .with_max_level(tracing::Level::INFO)
            .event_format(aviutl2::logger::AviUtl2Formatter)
            .with_writer(aviutl2::logger::AviUtl2LogWriter)
            .init();
        Ok(Self {
            trim: SubPlugin::new_filter_plugin(&info)?,
            deform: SubPlugin::new_filter_plugin(&info)?,
            align: SubPlugin::new_filter_plugin(&info)?,
            transform: SubPlugin::new_filter_plugin(&info)?,
            utf8: SubPlugin::new_script_module(&info)?,
            regex: SubPlugin::new_script_module(&info)?,
            kerning: SubPlugin::new_script_module(&info)?,
            hash: SubPlugin::new_script_module(&info)?,
            toml: SubPlugin::new_script_module(&info)?,
            vector: SubPlugin::new_script_module(&info)?,
            island: SubPlugin::new_script_module(&info)?,
        })
    }

    fn plugin_info(&self) -> aviutl2::generic::GenericPluginTable {
        aviutl2::generic::GenericPluginTable {
            name: "KineticType_H".to_string(),
            information: format!(
                "KineticType_H v{} by HexBrowns (fork of FlowType_K by Korarei)",
                env!("CARGO_PKG_VERSION")
            ),
        }
    }

    fn register(&mut self, registry: &mut aviutl2::generic::HostAppHandle) {
        font::init(&aviutl2::config::app_data_path().join("Font"));

        registry.register_filter_plugin(&self.align);
        registry.register_filter_plugin(&self.deform);
        registry.register_filter_plugin(&self.transform);
        registry.register_filter_plugin(&self.trim);

        registry.register_script_module(Some("Hash@KineticType_H"), &self.hash);
        registry.register_script_module(Some("Island@KineticType_H"), &self.island);
        registry.register_script_module(Some("Kerning@KineticType_H"), &self.kerning);
        registry.register_script_module(Some("Regex@KineticType_H"), &self.regex);
        registry.register_script_module(Some("UTF8@KineticType_H"), &self.utf8);
        registry.register_script_module(Some("Toml@KineticType_H"), &self.toml);
        registry.register_script_module(Some("Vector@KineticType_H"), &self.vector);

        EDIT_HANDLE.init(registry.create_edit_handle());
        menus::register(registry);
    }

    fn on_clear_cache(&mut self, _edit_section: &aviutl2::generic::EditSection) {
        modules::clear_cache();
        font::reset();
    }
}

impl Drop for KineticTypeH {
    fn drop(&mut self) {
        modules::clear_cache();
        font::deinit();
    }
}

// 本体が呼ぶ関数（GetCommonPluginTable / RegisterPlugin など）を書き出す。これが無いと読み込みで
// 「Failed to register common plugin. GetProcAddress() failed.」になる（ルール au2-rs-plugin「ビルド」）
aviutl2::register_generic_plugin!(KineticTypeH);
