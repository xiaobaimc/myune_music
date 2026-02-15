use flutter_rust_bridge::frb;
use serde::Serialize;
use std::path::Path;

// Lofty 相关的导入
use lofty::config::{ParseOptions, ParsingMode};
use lofty::file::TaggedFile;
use lofty::prelude::*;
use lofty::probe::Probe;
use lofty::read_from_path;
use lofty::tag::{Accessor, ItemKey};

#[derive(Default, Debug)]
#[frb(non_opaque)]
pub struct AudioInfoOptions {
    pub need_cover: bool,
    pub need_lyrics: bool,
    pub need_audio_props: bool,
    pub need_extra_tags: bool, // 包含:专辑艺术家、流派、年份
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
    pub year: Option<u32>,
    pub genre: Option<String>,
    pub album_artist: Option<String>,
}

fn read_tagged_file(path: &Path, options: &AudioInfoOptions) -> Result<TaggedFile, String> {
    // read_from_path
    if let Ok(file) = read_from_path(path) {
        let has_tag = file.primary_tag().is_some() || !file.tags().is_empty();
        let has_cover = !options.need_cover
            || file
                .primary_tag()
                .and_then(|t| t.pictures().first())
                .is_some();

        if has_tag && has_cover {
            return Ok(file);
        }
    }

    // Relaxed Probe
    Probe::open(path)
        .map_err(|e| e.to_string())?
        .options(
            ParseOptions::new()
                .parsing_mode(ParsingMode::Relaxed) // 宽容，救命
                .read_tags(true)
                .read_cover_art(options.need_cover)
                .read_properties(options.need_audio_props),
        )
        .read()
        .map_err(|e| e.to_string())
}

// 对Dart暴露的主函数

#[frb]
pub fn read_audio_info(path: String, options: AudioInfoOptions) -> Result<AudioInfo, String> {
    let path_ref = Path::new(&path);

    let tagged_file = read_tagged_file(path_ref, &options)?;

    let mut info = AudioInfo {
        title: None,
        artist: None,
        album: None,
        cover: None,
        lyrics: None,
        duration_ms: None,
        bitrate: None,
        sample_rate: None,
        year: None,
        genre: None,
        album_artist: None,
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

        if options.need_extra_tags {
            info.year = tag.year();

            if let Some(genre_str) = tag.genre() {
                info.genre = Some(genre_str.to_string());
            }

            if let Some(album_artist_str) = tag.get_string(&ItemKey::AlbumArtist) {
                info.album_artist = Some(album_artist_str.to_string());
            }
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
