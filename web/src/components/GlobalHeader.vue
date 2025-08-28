<script setup>
import { ref, onMounted, useTemplateRef } from 'vue'
import { RouterLink, useRoute } from 'vue-router'
import { GithubOutlined, ExclamationCircleOutlined } from '@ant-design/icons-vue'
import { Bot, Waypoints, LibraryBig, Settings } from 'lucide-vue-next';
import { onLongPress } from '@vueuse/core'

import { useInfoStore } from '@/stores/info'
import { useConfigStore } from '@/stores/config'
import UserInfoComponent from '@/components/UserInfoComponent.vue'
import DebugComponent from '@/components/DebugComponent.vue'

const infoStore = useInfoStore()
const configStore = useConfigStore()
const route = useRoute()

// Add state for GitHub stars
const githubStars = ref(0)
const isLoadingStars = ref(false)

// Fetch GitHub stars count
const fetchGithubStars = async () => {
  try {
    isLoadingStars.value = true
    const response = await fetch('https://api.github.com/repos/xerrors/Yuxi-Know')
    const data = await response.json()
    githubStars.value = data.stargazers_count
  } catch (error) {
    console.error('获取GitHub stars失败:', error)
  } finally {
    isLoadingStars.value = false
  }
}

// Add state for debug modal
const showDebugModal = ref(false)
const htmlRefHook = useTemplateRef('htmlRefHook')

// Setup long press for debug modal
onLongPress(
  htmlRefHook,
  () => {
    showDebugModal.value = true
  },
  {
    delay: 1000,
    modifiers: {
      prevent: true
    }
  }
)

// Handle debug modal close
const handleDebugModalClose = () => {
  showDebugModal.value = false
}

const mainList = [
  { name: '智能体', path: '/agent', icon: Bot, activeIcon: Bot },
  { name: '图谱', path: '/graph', icon: Waypoints, activeIcon: Waypoints },
  { name: '知识库', path: '/database', icon: LibraryBig, activeIcon: LibraryBig }
]

onMounted(() => {
  fetchGithubStars()
})
</script>

<template>
  <div class="global-header">
    <div class="header-left">
      <div class="logo" ref="htmlRefHook">
        <router-link to="/">
          <img :src="infoStore.organization.avatar">
        </router-link>
      </div>
      <span class="app-title">{{ infoStore.branding.name }}</span>
    </div>

    <div class="header-center">
      <RouterLink
        v-for="(item, index) in mainList"
        :key="index"
        :to="item.path"
        v-show="!item.hidden"
        class="nav-item"
        active-class="active"
      >
        <component class="icon" :is="route.path.startsWith(item.path) ? item.activeIcon : item.icon" size="20"/>
        <span class="text">{{ item.name }}</span>
      </RouterLink>
    </div>

    <div class="header-right">
      <div class="github nav-item">
        <a-tooltip placement="bottom">
          <template #title>欢迎 Star</template>
          <a href="https://github.com/xerrors/Yuxi-Know" target="_blank" class="github-link">
            <GithubOutlined class="icon" />
            <span v-if="githubStars > 0" class="github-stars">
              <span class="star-count">{{ (githubStars / 1000).toFixed(1) }}k</span>
            </span>
          </a>
        </a-tooltip>
      </div>

      <a-tooltip placement="bottom">
        <template #title>后端疑似没有正常启动或者正在繁忙中，请刷新一下或者检查 docker logs api-dev</template>
        <div class="nav-item warning" v-if="!configStore.config._config_items">
          <component class="icon" :is="ExclamationCircleOutlined" />
        </div>
      </a-tooltip>

      <div class="nav-item user-info">
        <UserInfoComponent display-mode="name" />
      </div>
    </div>

    <!-- Debug Modal -->
    <a-modal
      v-model:open="showDebugModal"
      title="调试面板"
      width="90%"
      :footer="null"
      @cancel="handleDebugModalClose"
      :maskClosable="true"
      :destroyOnClose="true"
      class="debug-modal"
    >
      <DebugComponent />
    </a-modal>
  </div>
</template>

<style lang="less" scoped>
.global-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0 16px;
  height: 48px;
  border-bottom: 1px solid var(--gray-200);
  background-color: var(--main-10);
  flex-shrink: 0;
  user-select: none;

  .header-left {
    display: flex;
    align-items: center;
    gap: 12px;

    .logo {
      width: 32px;
      height: 32px;
      cursor: pointer;

      img {
        width: 100%;
        height: 100%;
        border-radius: 4px;
      }
    }

    .app-title {
      font-size: 16px;
      font-weight: 600;
      color: var(--gray-900);
    }
  }

  .header-center {
    display: flex;
    align-items: center;
    gap: 16px;
    position: absolute;
    left: 50%;
    transform: translateX(-50%);

    .nav-item {
      display: flex;
      align-items: center;
      gap: 6px;
      padding: 6px 12px;
      border-radius: 6px;
      color: #333;
      text-decoration: none;
      transition: background-color 0.2s ease-in-out;

      .text {
        font-size: 14px;
        font-weight: 500;
      }

      &.active {
        background-color: var(--main-50);
        color: var(--main-color);
        font-weight: bold;
      }

      &:hover {
        background-color: var(--main-50);
      }
    }
  }

  .header-right {
    display: flex;
    align-items: center;
    gap: 20px;

    .nav-item {
      display: flex;
      align-items: center;
      font-size: 20px;
      color: #222;
      cursor: pointer;
      text-decoration: none;

      &.github {
        .github-link {
          display: flex;
          align-items: center;
          color: inherit;
          text-decoration: none;
        }

        .github-stars {
          display: flex;
          align-items: center;
          font-size: 12px;
          margin-left: 6px;

          .star-count {
            font-weight: 600;
          }
        }
      }

      &.warning {
        color: red;
      }

      &.setting {
        color: #333;
        &.active {
          color: var(--main-color);
        }
      }
    }
  }
}
</style>
