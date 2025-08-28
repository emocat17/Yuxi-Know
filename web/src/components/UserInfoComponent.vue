<template>
  <div class="user-info-component">
    <a-dropdown :trigger="['click']" v-if="userStore.isLoggedIn">
      <div class="user-info-dropdown">
        <div class="user-avatar" v-if="displayMode === 'full' || displayMode === 'icon' ">
          <SquareUserRound  size="22" stroke-width="1.7"  />
        </div>
        <div v-if="displayMode === 'full' || displayMode === 'name'" class="user-text-details">
          <span class="username">{{ userStore.username }}</span>
          <span class="separator">·</span>
          <span class="role">{{ userRoleText }}</span>
        </div>
      </div>
      <template #overlay>
          <a-menu>
          <a-menu-item key="username" disabled>
            <span class="user-menu-username">{{ userStore.username }}</span>
          </a-menu-item>
          <a-menu-item key="role" disabled>
            <span class="user-menu-role">{{ userRoleText }}</span>
          </a-menu-item>
          <a-menu-divider />
          <a-menu-item v-if="userStore.userRole === 'admin' || userStore.userRole === 'superadmin'" key="setting" @click="goToSetting">
            <SettingOutlined /> &nbsp;设置
          </a-menu-item>
          <a-menu-item key="logout" @click="logout">
            <LogoutOutlined /> &nbsp;退出登录
          </a-menu-item>
        </a-menu>
      </template>
    </a-dropdown>
    <a-button v-else-if="displayMode === 'full'" type="primary" @click="goToLogin">
      登录 / 注册
    </a-button>
    <div v-else class="login-icon" @click="goToLogin">
      <UserRoundCheck />
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useUserStore } from '@/stores/user';
import { LogoutOutlined, SettingOutlined } from '@ant-design/icons-vue';
import { message } from 'ant-design-vue';
import { SquareUserRound , UserRoundCheck } from 'lucide-vue-next';

const router = useRouter();
const userStore = useUserStore();

const props = defineProps({
  displayMode: {
    type: String,
    default: 'icon' // 'icon' or 'full' or 'name'
  }
})

// 用户角色显示文本
const userRoleText = computed(() => {
  switch (userStore.userRole) {
    case 'superadmin':
      return '超级管理员';
    case 'admin':
      return '管理员';
    case 'user':
      return '普通用户';
    default:
      return '未知角色';
  }
});

// 退出登录
const logout = () => {
  userStore.logout();
  message.success('已退出登录');
  // 跳转到首页
  router.push('/login');
};

// 前往登录页
const goToLogin = () => {
  router.push('/login');
};

// 前往设置页
const goToSetting = () => {
  router.push('/setting');
};
</script>

<style lang="less" scoped>
.user-info-component {
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--gray-900);
}

.user-info-dropdown {
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
  padding: 0px 8px;
  border-radius: 6px;
  transition: background-color 0.2s ease;

  &:hover {
    background-color: var(--gray-0);
  }
}

.user-avatar {
  width: 30px;
  height: 30px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: bold;
  font-size: 18px;
  position: relative;
  flex-shrink: 0;
  color: var(--gray-900);

  &:hover {
    opacity: 0.9;
  }
}

.user-text-details {
  display: flex;
  flex-direction: row;
  align-items: center;
  gap: 6px;

  .username {
    font-size: 14px;
    font-weight: 500;
    color: var(--gray-800);
  }

  .separator {
    color: var(--gray-400);
  }

  .role {
    font-size: 12px;
    color: var(--gray-500);
  }
}

.user-menu-username {
  font-weight: bold;
}

.user-menu-role {
  font-size: 12px;
  color: rgba(0, 0, 0, 0.45);
}

.login-icon {
  width: 30px;
  height: 30px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  border-radius: 50%;
  transition: background-color 0.3s;

  &:hover {
    background-color: rgba(0, 0, 0, 0.05);
  }
}
</style>
