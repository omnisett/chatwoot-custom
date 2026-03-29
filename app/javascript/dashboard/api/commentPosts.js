/* global axios */
import ApiClient from './ApiClient';

class CommentPostsAPI extends ApiClient {
  constructor() {
    super('comment_posts', { accountScoped: true });
  }

  get({ inboxId, platform, sortBy, page } = {}) {
    const params = {};
    if (inboxId) params.inbox_id = inboxId;
    if (platform) params.platform = platform;
    if (sortBy) params.sort_by = sortBy;
    if (page) params.page = page;

    return axios.get(this.url, { params });
  }

  getConversations(postId) {
    return axios.get(`${this.url}/${postId}`);
  }

  upsert(data) {
    return axios.post(`${this.url}/upsert`, data);
  }
}

export default new CommentPostsAPI();
