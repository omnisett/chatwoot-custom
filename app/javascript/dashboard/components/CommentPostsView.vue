<script setup>
/**
 * CommentPostsView — Grouped-by-post view of comment conversations.
 * Shows expandable post cards sorted by latest comment or post date.
 */
import { ref, computed, onMounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store.js';

import CommentPostCard from './CommentPostCard.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import IntersectionObserver from 'dashboard/components/IntersectionObserver.vue';

const props = defineProps({
  conversationInbox: { type: [String, Number], default: 0 },
});

const store = useStore();
const { t } = useI18n();

const posts = computed(() => store.getters['commentPosts/getPosts']);
const uiFlags = computed(() => store.getters['commentPosts/getUIFlags']);
const meta = computed(() => store.getters['commentPosts/getMeta']);
const sortBy = computed(() => store.getters['commentPosts/getSortBy']);

const sortOptions = [
  { key: 'latest_comment', label: 'Latest comment' },
  { key: 'post_date', label: 'Latest post' },
];

const platformOptions = [
  { key: '', label: 'All platforms' },
  { key: 'facebook', label: 'Facebook' },
  { key: 'instagram', label: 'Instagram' },
];

const activeSortBy = ref('latest_comment');
const activePlatform = ref('');

const hasMore = computed(() => {
  return posts.value.length < (meta.value.totalCount || 0);
});

const onSortChange = (newSort) => {
  activeSortBy.value = newSort;
  store.dispatch('commentPosts/setSortBy', newSort);
};

const onPlatformChange = (newPlatform) => {
  activePlatform.value = newPlatform;
  store.dispatch('commentPosts/setPlatformFilter', newPlatform);
};

const loadMore = () => {
  if (!uiFlags.value.isFetching && hasMore.value) {
    store.dispatch('commentPosts/loadMorePosts');
  }
};

const intersectionObserverOptions = { root: null, rootMargin: '100px', threshold: 0.1 };

onMounted(() => {
  if (props.conversationInbox) {
    store.dispatch('commentPosts/setInboxFilter', props.conversationInbox);
  } else {
    store.dispatch('commentPosts/fetchPosts', { page: 1 });
  }
});

watch(
  () => props.conversationInbox,
  (newVal) => {
    store.dispatch('commentPosts/setInboxFilter', newVal || '');
  }
);
</script>

<template>
  <div class="comment-posts-view flex flex-col h-full">
    <!-- Sort/Filter Bar -->
    <div class="flex items-center gap-2 px-3 py-2 border-b border-n-weak bg-n-surface-1">
      <!-- Sort dropdown -->
      <select
        :value="activeSortBy"
        class="text-xs border border-n-weak rounded px-2 py-1 bg-n-surface-1 text-n-slate-12 cursor-pointer"
        @change="onSortChange($event.target.value)"
      >
        <option
          v-for="opt in sortOptions"
          :key="opt.key"
          :value="opt.key"
        >
          {{ opt.label }}
        </option>
      </select>

      <!-- Platform filter -->
      <select
        :value="activePlatform"
        class="text-xs border border-n-weak rounded px-2 py-1 bg-n-surface-1 text-n-slate-12 cursor-pointer"
        @change="onPlatformChange($event.target.value)"
      >
        <option
          v-for="opt in platformOptions"
          :key="opt.key"
          :value="opt.key"
        >
          {{ opt.label }}
        </option>
      </select>

      <!-- Post count -->
      <span class="text-xs text-n-slate-11 ml-auto">
        {{ meta.totalCount || 0 }} posts
      </span>
    </div>

    <!-- Posts List -->
    <div class="flex-1 overflow-y-auto px-3 py-2">
      <div v-if="uiFlags.isFetching && !posts.length" class="flex justify-center py-8">
        <Spinner class="text-n-brand" />
      </div>

      <div v-else-if="!posts.length" class="flex flex-col items-center justify-center py-12 text-n-slate-11">
        <span class="i-lucide-message-square-off text-3xl mb-2" />
        <p class="text-sm">No comment posts found</p>
        <p class="text-xs mt-1">Comments from Facebook and Instagram will appear here grouped by post</p>
      </div>

      <template v-else>
        <CommentPostCard
          v-for="post in posts"
          :key="post.id"
          :post="post"
        />

        <div v-if="uiFlags.isFetching" class="flex justify-center py-4">
          <Spinner class="text-n-brand" />
        </div>

        <p
          v-else-if="!hasMore && posts.length"
          class="text-center text-xs text-n-slate-11 py-4"
        >
          All posts loaded
        </p>

        <IntersectionObserver
          v-else
          :options="intersectionObserverOptions"
          @observed="loadMore"
        />
      </template>
    </div>
  </div>
</template>

<style scoped>
.comment-posts-view {
  min-height: 0;
}
</style>
