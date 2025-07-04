use flutter_rust_bridge::frb;
#[cfg(target_os = "windows")]
use windows::{
    core::HSTRING,
    Foundation::{TypedEventHandler, TimeSpan},
    Media::{
        MediaPlaybackStatus, MediaPlaybackType, Playback::MediaPlayer,
        SystemMediaTransportControls, SystemMediaTransportControlsButton,
        SystemMediaTransportControlsButtonPressedEventArgs, SystemMediaTransportControlsTimelineProperties,
    },
    Storage::{
        FileProperties::ThumbnailMode,
        StorageFile,
        Streams::{DataWriter, InMemoryRandomAccessStream, RandomAccessStreamReference},
    },
};

use crate::frb_generated::StreamSink;

/// 系统媒体传输控件（SMTC）的 Flutter 接口
pub struct SmtcFlutter {
    #[cfg(target_os = "windows")]
    _smtc: SystemMediaTransportControls,
    #[cfg(target_os = "windows")]
    _player: MediaPlayer,
}

/// SMTC 控制事件类型
pub enum SMTCControlEvent {
    Play,
    Pause,
    Previous,
    Next,
    Unknown,
}

/// SMTC 播放状态
pub enum SMTCState {
    Paused,
    Playing,
}

impl SmtcFlutter {
    #[frb(sync)]
    pub fn new() -> Self {
        #[cfg(target_os = "windows")]
        return Self::_new().unwrap();
        #[cfg(not(target_os = "windows"))]
        return SmtcFlutter {};
    }

    pub fn subscribe_to_control_events(&self, sink: StreamSink<SMTCControlEvent>) {
        #[cfg(target_os = "windows")]
        self._smtc
            .ButtonPressed(&TypedEventHandler::<
                SystemMediaTransportControls,
                SystemMediaTransportControlsButtonPressedEventArgs,
            >::new(move |_, event| {
                let event = event.as_ref().unwrap().Button().unwrap();
                let event = match event {
                    SystemMediaTransportControlsButton::Play => SMTCControlEvent::Play,
                    SystemMediaTransportControlsButton::Pause => SMTCControlEvent::Pause,
                    SystemMediaTransportControlsButton::Next => SMTCControlEvent::Next,
                    SystemMediaTransportControlsButton::Previous => SMTCControlEvent::Previous,
                    _ => SMTCControlEvent::Unknown,
                };
                let _ = sink.add(event);

                Ok(())
            }))
            .unwrap();
    }

    pub fn update_state(&self, state: SMTCState) {
        #[cfg(target_os = "windows")]
        self._update_state(state).unwrap();
    }

    /// 更新 SMTC 显示信息
    /// 两种方式都支持：image_path (封面路径) 或 image_data (封面字节)
    pub fn update_display(
        &self,
        title: String,
        artist: String,
        image_path: Option<String>,
        image_data: Option<Vec<u8>>,
    ) {
        #[cfg(target_os = "windows")]
        self._update_display(
            HSTRING::from(title),
            HSTRING::from(artist),
            image_path.map(HSTRING::from),
            image_data,
        )
        .unwrap();
    }

    /// 更新时间轴信息
    pub fn update_timeline(&self, position: i64, duration: i64) {
        #[cfg(target_os = "windows")]
        self._update_timeline(position, duration).unwrap();
    }

    pub fn close(self) {
        #[cfg(target_os = "windows")]
        self._player.Close().unwrap();
    }
}

#[cfg(target_os = "windows")]
impl SmtcFlutter {
    fn _init_controls(smtc: &SystemMediaTransportControls) -> Result<(), windows::core::Error> {
        smtc.SetIsNextEnabled(true)?;
        smtc.SetIsPauseEnabled(true)?;
        smtc.SetIsPlayEnabled(true)?;
        smtc.SetIsPreviousEnabled(true)?;
        Ok(())
    }

    fn _new() -> Result<Self, windows::core::Error> {
        let _player = MediaPlayer::new()?;
        _player.CommandManager()?.SetIsEnabled(false)?;
        let _smtc = _player.SystemMediaTransportControls()?;
        Self::_init_controls(&_smtc)?;
        Ok(Self { _smtc, _player })
    }

    fn _update_state(&self, state: SMTCState) -> Result<(), windows::core::Error> {
        let status = match state {
            SMTCState::Playing => MediaPlaybackStatus::Playing,
            SMTCState::Paused => MediaPlaybackStatus::Paused,
        };
        self._smtc.SetPlaybackStatus(status)?;
        Ok(())
    }

    /// 路径或内存封面
    fn _update_display(
        &self,
        title: HSTRING,
        artist: HSTRING,
        image_path: Option<HSTRING>,
        image_data: Option<Vec<u8>>,
    ) -> Result<(), windows::core::Error> {
        let updater = self._smtc.DisplayUpdater()?;
        updater.SetType(MediaPlaybackType::Music)?;

        let music_properties = updater.MusicProperties()?;
        music_properties.SetTitle(&title)?;
        music_properties.SetArtist(&artist)?;

        if let Some(data) = image_data {
            let stream = InMemoryRandomAccessStream::new()?;
            let writer = DataWriter::CreateDataWriter(&stream)?;
            writer.WriteBytes(&data)?;
            writer.StoreAsync()?.get()?;
            writer.FlushAsync()?.get()?; // 确保刷新
            writer.DetachStream()?;
            stream.Seek(0)?; // 指针回到开头

            let reference = RandomAccessStreamReference::CreateFromStream(&stream)?;
            updater.SetThumbnail(&reference)?;
        } else if let Some(path) = image_path {
            // 如果没有内存封面，则使用路径封面
            let file = StorageFile::GetFileFromPathAsync(&path)?.get()?;
            let thumbnail = file
                .GetThumbnailAsyncOverloadDefaultSizeDefaultOptions(ThumbnailMode::MusicView)?
                .get()?;
            let reference = RandomAccessStreamReference::CreateFromStream(&thumbnail)?;
            updater.SetThumbnail(&reference)?;
        }

        updater.Update()?;

        if !(self._smtc.IsEnabled()?) {
            self._smtc.SetIsEnabled(true)?;
        }

        Ok(())
    }

    /// 内部更新时间轴信息
    fn _update_timeline(&self, position: i64, duration: i64) -> Result<(), windows::core::Error> {
        let timeline = SystemMediaTransportControlsTimelineProperties::new()?;
        timeline.SetStartTime(TimeSpan { Duration: 0 })?;
        // 设置当前进度
        timeline.SetPosition(TimeSpan {
            Duration: position * 10_000,
        })?;
        // 设置总时长
        timeline.SetEndTime(TimeSpan {
            Duration: duration * 10_000,
        })?;
        // 设置最小和最大可寻址时间
        timeline.SetMinSeekTime(TimeSpan { Duration: 0 })?;
        timeline.SetMaxSeekTime(TimeSpan {
            Duration: duration * 10_000,
        })?;
        // 更新时间轴
        self._smtc.UpdateTimelineProperties(&timeline)?;

        Ok(())
    }
}