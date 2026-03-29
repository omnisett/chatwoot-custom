import CommentPostsAPI from '../../api/commentPosts';

const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isFetchingConversations: false,
  },
  meta: {
    totalCount: 0,
    page: 1,
  },
  // Map of post ID → expanded conversations
  postConversations: {},
  // Currently expanded post IDs
  expandedPosts: {},
  // Sort mode: 'latest_comment' or 'post_date'
  sortBy: 'latest_comment',
  // Filter by platform
  platformFilter: '',
  // Filter by inbox
  inboxFilter: '',
};

const getters = {
  getPosts: $state => $state.records,
  getUIFlags: $state => $state.uiFlags,
  getMeta: $state => $state.meta,
  getSortBy: $state => $state.sortBy,
  getPlatformFilter: $state => $state.platformFilter,
  getInboxFilter: $state => $state.inboxFilter,
  getPostConversations: $state => postId =>
    $state.postConversations[postId] || [],
  isPostExpanded: $state => postId => !!$state.expandedPosts[postId],
};

const SET_POSTS = 'SET_POSTS';
const APPEND_POSTS = 'APPEND_POSTS';
const SET_META = 'SET_META';
const SET_UI_FLAG = 'SET_UI_FLAG';
const SET_POST_CONVERSATIONS = 'SET_POST_CONVERSATIONS';
const TOGGLE_POST_EXPANDED = 'TOGGLE_POST_EXPANDED';
const SET_SORT_BY = 'SET_SORT_BY';
const SET_PLATFORM_FILTER = 'SET_PLATFORM_FILTER';
const SET_INBOX_FILTER = 'SET_INBOX_FILTER';
const UPDATE_POST = 'UPDATE_POST';

const mutations = {
  [SET_POSTS]($state, posts) {
    $state.records = posts;
  },
  [APPEND_POSTS]($state, posts) {
    const existingIds = new Set($state.records.map(p => p.id));
    const newPosts = posts.filter(p => !existingIds.has(p.id));
    $state.records = [...$state.records, ...newPosts];
  },
  [SET_META]($state, meta) {
    $state.meta = meta;
  },
  [SET_UI_FLAG]($state, { key, value }) {
    $state.uiFlags[key] = value;
  },
  [SET_POST_CONVERSATIONS]($state, { postId, conversations }) {
    $state.postConversations = {
      ...$state.postConversations,
      [postId]: conversations,
    };
  },
  [TOGGLE_POST_EXPANDED]($state, postId) {
    const current = !!$state.expandedPosts[postId];
    $state.expandedPosts = {
      ...$state.expandedPosts,
      [postId]: !current,
    };
  },
  [SET_SORT_BY]($state, sortBy) {
    $state.sortBy = sortBy;
  },
  [SET_PLATFORM_FILTER]($state, platform) {
    $state.platformFilter = platform;
  },
  [SET_INBOX_FILTER]($state, inboxId) {
    $state.inboxFilter = inboxId;
  },
  [UPDATE_POST]($state, updatedPost) {
    const idx = $state.records.findIndex(p => p.id === updatedPost.id);
    if (idx !== -1) {
      $state.records.splice(idx, 1, {
        ...$state.records[idx],
        ...updatedPost,
      });
    }
  },
};

const actions = {
  async fetchPosts({ commit, state: $state }, { page = 1 } = {}) {
    commit(SET_UI_FLAG, { key: 'isFetching', value: true });
    try {
      const { data } = await CommentPostsAPI.get({
        inboxId: $state.inboxFilter || undefined,
        platform: $state.platformFilter || undefined,
        sortBy: $state.sortBy,
        page,
      });
      const payload = data?.data?.payload || [];
      const meta = data?.data?.meta || {};

      if (page === 1) {
        commit(SET_POSTS, payload);
      } else {
        commit(APPEND_POSTS, payload);
      }
      commit(SET_META, { totalCount: meta.total_count || 0, page });
    } catch (error) {
      // silent
    } finally {
      commit(SET_UI_FLAG, { key: 'isFetching', value: false });
    }
  },

  async fetchPostConversations({ commit }, postId) {
    commit(SET_UI_FLAG, { key: 'isFetchingConversations', value: true });
    try {
      const { data } = await CommentPostsAPI.getConversations(postId);
      const conversations = data?.data?.conversations || [];
      commit(SET_POST_CONVERSATIONS, { postId, conversations });
    } catch (error) {
      // silent
    } finally {
      commit(SET_UI_FLAG, { key: 'isFetchingConversations', value: false });
    }
  },

  togglePostExpanded({ commit, dispatch, state: $state }, postId) {
    commit(TOGGLE_POST_EXPANDED, postId);
    // Fetch conversations when expanding if not already loaded
    if (!$state.expandedPosts[postId] && !$state.postConversations[postId]) {
      // Was just collapsed, no need to fetch
    } else if ($state.expandedPosts[postId] && !$state.postConversations[postId]?.length) {
      dispatch('fetchPostConversations', postId);
    }
  },

  setSortBy({ commit, dispatch }, sortBy) {
    commit(SET_SORT_BY, sortBy);
    dispatch('fetchPosts', { page: 1 });
  },

  setPlatformFilter({ commit, dispatch }, platform) {
    commit(SET_PLATFORM_FILTER, platform);
    dispatch('fetchPosts', { page: 1 });
  },

  setInboxFilter({ commit, dispatch }, inboxId) {
    commit(SET_INBOX_FILTER, inboxId);
    dispatch('fetchPosts', { page: 1 });
  },

  loadMorePosts({ dispatch, state: $state }) {
    const nextPage = ($state.meta.page || 1) + 1;
    dispatch('fetchPosts', { page: nextPage });
  },
};

export default {
  namespaced: true,
  state,
  getters,
  mutations,
  actions,
};
