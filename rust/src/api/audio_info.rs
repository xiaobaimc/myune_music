use flutter_rust_bridge::frb;
use serde::Serialize;
use std::path::Path;

// Lofty 相关的导入
use lofty::prelude::*;
use lofty::read_from_path;
use lofty::tag::{Accessor, ItemKey};

#[derive(Debug)]
#[frb(non_opaque)]
pub struct AudioInfoOptions {
    pub need_cover: bool,
    pub need_lyrics: bool,
    pub need_audio_props: bool,
}

#[derive(Debug, Serialize)]
#[frb(non_opaque)]
pub struct AudioInfo {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub cover: Option<Vec<u8>>,
    pub lyrics: Option<String>,
    pub duration_ms: Option<u64>,
    pub bitrate: Option<u32>,
    pub sample_rate: Option<u32>,
}

// 对Dart暴露的主函数

#[frb]
pub fn read_audio_info(path: String, options: AudioInfoOptions) -> Result<AudioInfo, String> {
    let path_ref = Path::new(&path);

    let tagged_file = read_from_path(path_ref).map_err(|e| e.to_string())?;

    let mut info = AudioInfo {
        title: None,
        artist: None,
        album: None,
        cover: None,
        lyrics: None,
        duration_ms: None,
        bitrate: None,
        sample_rate: None,
    };

    // 处理标签信息
    if let Some(tag) = tagged_file
        .primary_tag()
        .or_else(|| tagged_file.first_tag())
    {
        info.title = tag.title().map(|s| s.to_string());
        info.artist = tag.artist().map(|s| s.to_string());
        info.album = tag.album().map(|s| s.to_string());

        if options.need_cover {
            // 获取第一张图片,不指定类型
            if let Some(pic) = tag.pictures().first() {
                info.cover = Some(pic.data().to_vec());
            }
        }

        if options.need_lyrics {
            info.lyrics = tag.get_string(&ItemKey::Lyrics).map(|s| s.to_string());
        }
    }

    // 只在需要时读取音频属性，避免未使用警告
    if options.need_audio_props {
        let props = tagged_file.properties();

        info.duration_ms = Some(props.duration().as_millis() as u64);
        info.sample_rate = props.sample_rate();
        // 优先用音频码率，没的话用整体码率
        info.bitrate = props.audio_bitrate().or(props.overall_bitrate());
    }

    Ok(info)
}
