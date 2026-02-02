<script setup>
import { ref, watch, onMounted } from 'vue';

const serverIp = ref('192.168.0.17');
const files = ref([]);
const selectedFiles = ref([]);
const customTitles = ref({}); // id: customTitle (확장자 제외)
const fileExts = ref({}); // id: 확장자
const originalTitles = ref({}); // id: 원본 title
const page = ref(0);
const pageSize = 30;
const loading = ref(false);
const noMore = ref(false);
const scrollContainer = ref(null);

function resetAndFetchFiles() {
  files.value = [];
  page.value = 0;
  noMore.value = false;
  fetchFiles();
}

function fetchFiles() {
  if (!serverIp.value || loading.value || noMore.value) return;
  console.log('[fetchFiles] 요청 시작', serverIp.value, page.value, pageSize);
  loading.value = true;
  fetch(`http://${serverIp.value}:5000/list?page=${page.value}&size=${pageSize}`)
    .then(res => {
      console.log('[fetchFiles] fetch 성공', res.status);
      return res.json();
    })
    .then(data => {
      console.log('[fetchFiles] 데이터 파싱', Array.isArray(data) ? data.length : data);
      if (Array.isArray(data) && data.length > 0) {
        // 중복 id 방지
        const existingIds = new Set(files.value.map(f => f.id));
        const newItems = data.filter(f => !existingIds.has(f.id));
        // 확장자, 원본 title, customTitle 초기화
        newItems.forEach(f => {
          if (f.title) {
            originalTitles.value[f.id] = f.title;
            const extMatch = f.title.match(/\.([^.]+)$/);
            fileExts.value[f.id] = extMatch ? extMatch[1] : '';
            // customTitle이 없으면 확장자 제외한 이름으로 초기화
            if (customTitles.value[f.id] === undefined) {
              customTitles.value[f.id] = extMatch ? f.title.slice(0, -(extMatch[0].length)) : f.title;
            }
          }
        });
        files.value = [...files.value, ...newItems];
        page.value++;
        if (data.length < pageSize) noMore.value = true;
      } else {
        noMore.value = true;
      }
    })
    .catch(err => {
      console.error('[fetchFiles] 에러', err);
      if (page.value === 0) files.value = [];
    })
    .finally(() => {
      console.log('[fetchFiles] finally, loading=false');
      loading.value = false;
    });
}

function onScroll(e) {
  const el = e.target;
  if (el.scrollTop + el.clientHeight >= el.scrollHeight - 100) {
    fetchFiles();
  }
}


onMounted(resetAndFetchFiles);

function toggleFile(filename) {
  if (selectedFiles.value.includes(filename)) {
    selectedFiles.value = selectedFiles.value.filter(f => f !== filename);
  } else {
    selectedFiles.value = [...selectedFiles.value, filename];
  }
}

function clearSelectedFiles() {
  selectedFiles.value = [];
}

function downloadFile(id) {
  let filename = '';
  // 사용자가 수정한 이름이 있으면 그걸, 아니면 원본 title에서 확장자 제거한 이름
  if (customTitles.value[id] && customTitles.value[id].trim() !== '') {
    filename = customTitles.value[id].trim();
  } else if (originalTitles.value[id]) {
    const extMatch = originalTitles.value[id].match(/\.([^.]+)$/);
    filename = extMatch ? originalTitles.value[id].slice(0, -(extMatch[0].length)) : originalTitles.value[id];
  }
  let url = `http://${serverIp.value}:5000/file/${id}`;
  if (filename) {
    url += `?filename=${encodeURIComponent(filename)}`;
  }
  window.open(url);
}

function downloadSelected() {
  if (selectedFiles.value.length > 5) {
    alert('여러 파일을 동시에 다운로드하면 브라우저 팝업 차단에 걸릴 수 있습니다. 팝업 허용을 해주세요.');
  }
  selectedFiles.value.forEach(downloadFile);
}

function onTitleEnter(id, event) {
  // 체크박스 체크
  if (!selectedFiles.value.includes(id)) {
    selectedFiles.value = [...selectedFiles.value, id];
  }
  // 다음 입력란으로 포커스 이동
  const idx = files.value.findIndex(f => f.id === id);
  if (idx !== -1 && idx < files.value.length - 1) {
    // 다음 input의 tabindex는 idx+2
    const nextInput = document.querySelector('input[tabindex="' + (idx + 2) + '"]');
    if (nextInput) {
      nextInput.focus();
      nextInput.select();
      event.preventDefault();
    }
  }
}
</script>

<template>
  <div>
    <h1>갤러리 파일 목록</h1>
    <div style="margin: 10px 0">
      <label>서버 IP: </label>
      <input
        type="text"
        v-model="serverIp"
        style="margin-right: 8px"
      />
      <button @click="resetAndFetchFiles" style="margin-right: 8px;">
        서버 파일 목록 불러오기
      </button>
      <button @click="downloadSelected" :disabled="selectedFiles.length === 0" style="margin-right: 8px;">
        선택 다운로드 ({{ selectedFiles.length }})
      </button>
      <button @click="clearSelectedFiles" :disabled="selectedFiles.length === 0">
        선택 해제
      </button>
    </div>
    <div
      style="display: flex; flex-wrap: wrap; min-height: 200px; height: 70vh; overflow-y: auto;"
      @scroll.passive="onScroll"
      ref="scrollContainer"
    >
      <div
        v-for="f in files"
        :key="f.id"
        style="margin: 10px; border: 1px solid #ccc; padding: 8px; border-radius: 6px; cursor: pointer;"
        @click="toggleFile(f.id)"
      >
        <input
          type="checkbox"
          :checked="selectedFiles.includes(f.id)"
          @change.stop="toggleFile(f.id)"
          style="margin-bottom: 4px"
        />
        <div style="position: relative; width: 128px; height: 128px; margin-bottom: 4px;">
          <img
            :src="`http://${serverIp}:5000/thumbnail/${f.id}`"
            :alt="f.title || f.id"
            style="width: 128px; height: 128px; display: block; border-radius: 4px;"
          />
          <span v-if="fileExts[f.id]" style="position: absolute; top: 4px; left: 4px; background: rgba(0,0,0,0.7); color: #fff; font-size: 12px; padding: 2px 6px; border-radius: 8px; letter-spacing: 1px;">
            .{{ fileExts[f.id] }}
          </span>
        </div>
        <div style="margin-bottom: 4px;">
          <input
            type="text"
            v-model="customTitles[f.id]"
            style="width: 120px;"
            :tabindex="files.findIndex(x => x.id === f.id) + 1"
            :placeholder="fileExts[f.id] ? `파일명 (확장자: .${fileExts[f.id]})` : '파일명'"
            @keydown.enter="onTitleEnter(f.id, $event)"
            @click.stop
          />
        </div>
        <button @click.stop="downloadFile(f.id)">다운로드</button>
      </div>
      <div v-if="loading" style="width: 100%; text-align: center; margin: 20px 0;">로딩 중...</div>
      <div v-if="noMore && files.length > 0" style="width: 100%; text-align: center; margin: 20px 0; color: #888;">더 이상 파일이 없습니다.</div>
    </div>
  </div>
</template>


