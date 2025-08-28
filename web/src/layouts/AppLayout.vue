<script setup>
import { ref, onMounted } from 'vue'
import { RouterView, useRoute } from 'vue-router'

import { useConfigStore } from '@/stores/config'
import { useDatabaseStore } from '@/stores/database'
import { useInfoStore } from '@/stores/info'
import GlobalHeader from '@/components/GlobalHeader.vue' // 导入新组件

const configStore = useConfigStore()
const databaseStore = useDatabaseStore()
const infoStore = useInfoStore()

const getRemoteConfig = () => {
  configStore.refreshConfig()
}

const getRemoteDatabase = () => {
  databaseStore.getDatabaseInfo()
}

onMounted(async () => {
  // 加载信息配置
  await infoStore.loadInfoConfig()
  // 加载其他配置
  getRemoteConfig()
  getRemoteDatabase()
})

// 打印当前页面的路由信息，使用 vue3 的 setup composition API
const route = useRoute()
console.log(route)
</script>

<template>
  <div class="app-layout">
    <GlobalHeader />
    <div class="main-content">
      <router-view v-slot="{ Component, route }" id="app-router-view">
        <keep-alive v-if="route.meta.keepAlive !== false">
          <component :is="Component" />
        </keep-alive>
        <component :is="Component" v-else />
      </router-view>
    </div>

    <div class="header-mobile">
      <RouterLink to="/chat" class="nav-item" active-class="active">对话</RouterLink>
      <RouterLink to="/database" class="nav-item" active-class="active">知识</RouterLink>
      <RouterLink to="/setting" class="nav-item" active-class="active">设置</RouterLink>
    </div>
  </div>
</template>

<style lang="less" scoped>
@import '@/assets/css/main.css';

.app-layout {
  display: flex;
  flex-direction: column; // 垂直布局
  width: 100%;
  height: 100vh;
  min-width: var(--min-width);

  .header-mobile {
    display: none;
  }
}

.main-content {
  display: flex;
  flex-direction: row;
  flex-grow: 1;
  height: calc(100vh - 50px); // 减去header高度
  overflow: hidden;
}

#app-router-view {
  height: 100%;
  max-width: 100%;
  user-select: none;
  flex: 1 1 auto;
  overflow-y: auto;
}

@media (max-width: 520px) {
  .app-layout {
    flex-direction: column-reverse;

    .main-content {
      display: contents; // 在移动端让sidebar和main-view恢复正常文档流
    }
  }
  .app-layout .header-mobile {
    display: flex;
    flex-direction: row;
    width: 100%;
    padding: 0 20px;
    justify-content: space-around;
    align-items: center;
    flex: 0 0 60px;
    border-right: none;
    height: 40px;

    .nav-item {
      text-decoration: none;
      width: 40px;
      color: var(--gray-900);
      font-size: 1rem;
      font-weight: bold;
      transition: color 0.1s ease-in-out, font-size 0.1s ease-in-out;

      &.active {
        color: black;
        font-size: 1.1rem;
      }
    }
  }
  .app-layout .chat-box::webkit-scrollbar {
    width: 0;
  }
}
</style>
