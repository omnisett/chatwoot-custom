<script setup>
/**
 * CommentPostCard — A single post card showing post info + expandable list of conversations.
 * Resembles Facebook's post-with-comments layout.
 */
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store.js';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  post: { type: Object, required: true },
});

const store = useStore();
const router = useRouter();
const { t } = useI18n();
const currentAccountId = useMapGetter('getCurrentAccountId');

const isExpanded = computed(() =>
  store.getters['commentPosts/isPostExpanded'](props.post.id)
);
const conversations = computed(() =>
  store.getters['commentPosts/getPostConversations'](props.post.id)
);
const isFetchingConversations = computed(
  () => store.getters['commentPosts/getUIFlags'].isFetchingConversations
);

const platformIcon = computed(() => {
  return props.post.platform === 'instagram'
    ? 'i-lucide-instagram'
    : 'i-lucide-facebook';
});

const platformColor = computed(() => {
  return props.post.platform === 'instagram'
    ? 'text-pink-500'
    : 'text-blue-600';
});

const postTitle = computed(() => {
  if (props.post.post_text) {
    return props.post.post_text;
  }
  return `Post ${props.post.post_id}`;
});

const postDate = computed(() => {
  const d = props.post.post_created_at || props.post.created_at;
  if (!d) return '';
  return new Date(d).toLocaleDateString('he-IL', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
});

const lastCommentDate = computed(() => {
  if (!props.post.last_comment_at) return '';
  return new Date(props.post.last_comment_at).toLocaleDateString('he-IL', {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  });
});

const toggleExpand = () => {
  store.dispatch('commentPosts/togglePostExpanded', props.post.id);
};

const openConversation = (conversationId) => {
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: currentAccountId.value,
      conversation_id: conversationId,
    },
  });
};

const openPostLink = () => {
  if (props.post.post_permalink) {
    window.open(props.post.post_permalink, '_blank');
  }
};
</script>

<template>
  <div class="comment-post-card border border-n-weak rounded-lg mb-3 overflow-hidden bg-n-surface-1">
    <!-- Post Header -->
    <div
      class="flex items-start gap-3 p-3 cursor-pointer hover:bg-n-alpha-1 transition-colors"
      @click="toggleExpand"
    >
      <!-- Platform icon -->
      <div class="flex-shrink-0 mt-0.5">
        <span :class="[platformIcon, platformColor, 'text-xl']" />
      </div>

      <!-- Post content preview -->
      <div class="flex-1 min-w-0">
        <p class="text-sm font-medium text-n-slate-12 line-clamp-2">
          {{ postTitle }}
        </p>
        <div class="flex items-center gap-3 mt-1 text-xs text-n-slate-11">
          <span v-if="postDate">{{ postDate }}</span>
          <span class="flex items-center gap-1">
            <span class="i-lucide-message-circle text-xs" />
            {{ post.conversations_count }}
            {{ post.conversations_count === 1 ? 'comment' : 'comments' }}
          </span>
          <span v-if="lastCommentDate" class="flex items-center gap-1">
            <span class="i-lucide-clock text-xs" />
            {{ lastCommentDate }}
          </span>
        </div>
      </div>

      <!-- Post image thumbnail -->
      <div
        v-if="post.post_media_url && post.post_media_type !== 'text'"
        class="flex-shrink-0 w-12 h-12 rounded overflow-hidden"
      >
        <img
          :src="post.post_media_url"
          alt=""
          class="w-full h-full object-cover"
          loading="lazy"
        />
      </div>

      <!-- Expand/collapse chevron -->
      <div class="flex-shrink-0 mt-1">
        <span
          :class="[
            isExpanded ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down',
            'text-n-slate-11 text-sm'
          ]"
        />
      </div>
    </div>

    <!-- External link -->
    <div
      v-if="post.post_permalink"
      class="px-3 pb-2 -mt-1"
    >
      <button
        class="text-xs text-n-brand hover:underline flex items-center gap-1"
        @click.stop="openPostLink"
      >
        <span class="i-lucide-external-link text-xs" />
        Open on {{ post.platform === 'instagram' ? 'Instagram' : 'Facebook' }}
      </button>
    </div>

    <!-- Expanded conversations list -->
    <div v-if="isExpanded" class="border-t border-n-weak">
      <div
        v-if="isFetchingConversations && !conversations.length"
        class="flex justify-center py-4"
      >
        <Spinner class="text-n-brand" />
      </div>

      <div v-else-if="!conversations.length" class="p-4 text-center text-sm text-n-slate-11">
        No conversations yet
      </div>

      <div v-else class="divide-y divide-n-weak">
        <div
          v-for="conv in conversations"
          :key="conv.id"
          class="flex items-center gap-3 px-3 py-2.5 cursor-pointer hover:bg-n-alpha-1 transition-colors"
          @click="openConversation(conv.id)"
        >
          <!-- Contact avatar -->
          <div class="flex-shrink-0 w-8 h-8 rounded-full bg-n-alpha-2 flex items-center justify-center text-xs font-medium text-n-slate-11">
            <img
              v-if="conv.contact?.thumbnail"
              :src="conv.contact.thumbnail"
              class="w-full h-full rounded-full object-cover"
            />
            <span v-else>{{ (conv.contact?.name || '?')[0] }}</span>
          </div>

          <!-- Conversation info -->
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              <span class="text-sm font-medium text-n-slate-12 truncate">
                {{ conv.contact?.name || 'Unknown' }}
              </span>
              <span
                :class="[
                  'text-[10px] px-1.5 py-0.5 rounded-full font-medium',
                  conv.status === 'open' ? 'bg-green-100 text-green-700' :
                  conv.status === 'resolved' ? 'bg-gray-100 text-gray-600' :
                  conv.status === 'pending' ? 'bg-yellow-100 text-yellow-700' :
                  'bg-blue-100 text-blue-600'
                ]"
              >
                {{ conv.status }}
              </span>
            </div>
            <p
              v-if="conv.last_message?.content"
              class="text-xs text-n-slate-11 truncate mt-0.5"
            >
              {{ conv.last_message.content }}
            </p>
          </div>

          <!-- Message count + time -->
          <div class="flex-shrink-0 text-right">
            <div class="text-xs text-n-slate-11">
              {{ conv.messages_count }} msgs
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.comment-post-card {
  transition: box-shadow 0.15s ease;
}
.comment-post-card:hover {
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
}
</style>
