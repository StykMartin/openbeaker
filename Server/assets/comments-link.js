
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.

;(function () {

window.CommentsLink = Backbone.View.extend({
    // This view is using DOM methods instead of a JST template for speed, 
    // since it's in the hot path for task results.
    initialize: function () {
        this.listenTo(this.model.get('comments'), 'reset add remove', this.render);
        this.render();
    },
    render: function () {
        this.$el.empty();
        if (this.model.get('can_comment') || !this.model.get('comments').isEmpty()) {
            var comments = this.model.get('comments');
            var comments_link = document.createElement('a');
            comments_link.href = '#';
            comments_link.className = 'comments-link';
            if (comments.size()) {
                comments_link.appendChild(document.createTextNode(comments.size().toString()));
                comments_link.appendChild(document.createTextNode(' '));
            }
            var comments_icon = document.createElement('i');
            comments_icon.className = 'fa fa-comment-o';
            var comments_icon_arialabel = document.createAttribute('aria-label');
            comments_icon_arialabel.value = 'comments';
            comments_icon.setAttributeNode(comments_icon_arialabel);
            comments_link.appendChild(comments_icon);
            this.el.appendChild(comments_link);
            $(comments_link).beaker_popover({
                model: this.model,
                view_type: CommentsPopover,
            });
        }
        return this;
    },
});

var CommentsPopover = BeakerPopoverView.extend({
    className: 'popover comments-popover',
    render: function () {
        BeakerPopoverView.prototype.render.apply(this);
        new CommentsList({model: this.model}).$el
            .appendTo(this.$('.popover-content'));
        if (this.model.get('can_comment')) {
            new CommentForm({model: this.model}).$el
                .appendTo(this.$('.popover-content'));
        }
    },
});

var CommentsList = Backbone.View.extend({
    template: JST['comments-list'],
    initialize: function (options) {
        this.listenTo(this.model.get('comments'), 'reset add remove', this.render);
        this.render();
    },
    render: function () {
        this.$el.html(this.template(this.model.attributes));
        if (!this.model.get('comments').isEmpty()) {
            this.$el.addClass('comments');
        }
        return this;
    },
});

var CommentForm = Backbone.View.extend({
    events: {
        'submit form.new-comment': 'add_comment',
        'keydown': 'keydown',
    },
    template: JST['comment-form'],
    className: 'comment-form',
    initialize: function (options) {
        this.render();
    },
    render: function () {
        this.$el.html(this.template(this.model.attributes));
        return this;
    },
    keydown: function (evt) {
        if ((evt.keyCode == 10 || evt.keyCode == 13) && evt.ctrlKey) {
            // submit the form on Ctrl-Enter
            evt.preventDefault();
            this.$('form').submit();
        }
    },
    add_comment: function (evt) {
        evt.preventDefault();
        this.$('.sync-status').empty();
        this.$('button').button('loading');
        var comment = this.$('textarea[name=comment]').val();
        this.model.get('comments').create({comment: comment}, {
            wait: true,
            success: _.bind(this.save_success, this),
            error: _.bind(this.save_error, this),
        });
    },
    save_success: function (model, xhr, options) {
        this.$('button').button('reset');
        this.$('textarea[name=comment]').val('');
    },
    save_error: function (model, xhr, options) {
        alert_for_xhr(xhr).appendTo(this.$('.sync-status'));
        this.$('button').button('reset');
    },
});

})();
